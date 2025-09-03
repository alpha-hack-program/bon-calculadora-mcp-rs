use serde::{Deserialize, Serialize, Deserializer, de::Error as DeError};
use zen_engine::DecisionEngine;
use zen_engine::model::DecisionContent;
use zen_engine::{EvaluationError, NodeError};
use std::fmt;

use rmcp::{
    ServerHandler,
    handler::server::{router::tool::ToolRouter, tool::Parameters},
    model::{ServerCapabilities, ServerInfo, CallToolResult, Content},
    ErrorData as McpError,
    schemars, tool, tool_handler, tool_router,
};

// =================== ESTRUCTURAS DE ERROR ===================

#[derive(Debug, Deserialize)]
pub struct ValidationError {
    pub message: String,
    pub path: String,
}

#[derive(Debug, Deserialize)]
pub struct ValidationErrorSource {
    pub errors: Vec<ValidationError>,
}

#[derive(Debug, Deserialize)]
pub struct ValidationErrorDetails {
    pub source: ValidationErrorSource,
    #[serde(rename = "type")]
    #[allow(dead_code)]
    pub error_type: String,
}

#[derive(Debug)]
pub enum ExcedenciaError {
    ValidationError(Vec<ValidationError>),
    ZenEngineError(EvaluationError),
    SerializationError(serde_json::Error),
}

impl fmt::Display for ExcedenciaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ExcedenciaError::ValidationError(errors) => {
                write!(f, "Errores de validación:\n")?;
                for error in errors {
                    write!(f, "  - {}: {}\n", error.path, error.message)?;
                }
                Ok(())
            },
            ExcedenciaError::ZenEngineError(e) => write!(f, "Error del motor de decisión: {}", e),
            ExcedenciaError::SerializationError(e) => write!(f, "Error de serialización: {}", e),
        }
    }
}

impl std::error::Error for ExcedenciaError {}

impl From<EvaluationError> for ExcedenciaError {
    fn from(error: EvaluationError) -> Self {
        ExcedenciaError::ZenEngineError(error)
    }
}

impl From<serde_json::Error> for ExcedenciaError {
    fn from(error: serde_json::Error) -> Self {
        ExcedenciaError::SerializationError(error)
    }
}

// =================== FUNCIONES AUXILIARES ===================

/// Deserializa un valor que puede ser bool o string ("true"/"false")
fn deserialize_bool_or_string<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: Deserializer<'de>,
{
    use serde::de::Visitor;
    use std::fmt;

    struct BoolOrStringVisitor;

    impl<'de> Visitor<'de> for BoolOrStringVisitor {
        type Value = bool;

        fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
            formatter.write_str("bool or string")
        }

        fn visit_bool<E>(self, value: bool) -> Result<bool, E>
        where
            E: DeError,
        {
            Ok(value)
        }

        fn visit_str<E>(self, value: &str) -> Result<bool, E>
        where
            E: DeError,
        {
            match value.to_lowercase().as_str() {
                "true" => Ok(true),
                "false" => Ok(false),
                _ => Err(DeError::custom(format!("invalid boolean string: {}", value))),
            }
        }

        fn visit_string<E>(self, value: String) -> Result<bool, E>
        where
            E: DeError,
        {
            self.visit_str(&value)
        }
    }

    deserializer.deserialize_any(BoolOrStringVisitor)
}

/// Deserializa un valor que puede ser f64 o string numérico
fn deserialize_f64_or_string<'de, D>(deserializer: D) -> Result<Option<f64>, D::Error>
where
    D: Deserializer<'de>,
{
    use serde::de::Visitor;
    use std::fmt;

    struct F64OrStringVisitor;

    impl<'de> Visitor<'de> for F64OrStringVisitor {
        type Value = Option<f64>;

        fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
            formatter.write_str("f64, string, or null")
        }

        fn visit_f64<E>(self, value: f64) -> Result<Option<f64>, E>
        where
            E: DeError,
        {
            Ok(Some(value))
        }

        fn visit_i64<E>(self, value: i64) -> Result<Option<f64>, E>
        where
            E: DeError,
        {
            Ok(Some(value as f64))
        }

        fn visit_u64<E>(self, value: u64) -> Result<Option<f64>, E>
        where
            E: DeError,
        {
            Ok(Some(value as f64))
        }

        fn visit_str<E>(self, value: &str) -> Result<Option<f64>, E>
        where
            E: DeError,
        {
            value.parse::<f64>()
                .map(Some)
                .map_err(|_| DeError::custom(format!("invalid number string: {}", value)))
        }

        fn visit_string<E>(self, value: String) -> Result<Option<f64>, E>
        where
            E: DeError,
        {
            self.visit_str(&value)
        }

        fn visit_none<E>(self) -> Result<Option<f64>, E>
        where
            E: DeError,
        {
            Ok(None)
        }

        fn visit_unit<E>(self) -> Result<Option<f64>, E>
        where
            E: DeError,
        {
            Ok(None)
        }
    }

    deserializer.deserialize_any(F64OrStringVisitor)
}

// =================== ESTRUCTURAS DE DATOS ===================

// Direct parameters structure for MCP (flattened)
#[derive(Debug, Serialize, Deserialize, PartialEq, schemars::JsonSchema)]
pub struct ExcedenciaDirectParams {
    #[schemars(description = "Relación familiar con la persona que necesita cuidado. VALORES VÁLIDOS: 'padre', 'madre', 'hijo', 'hija', 'conyuge', 'pareja', 'esposo', 'esposa', 'mujer', 'marido'. Ejemplo: 'madre'")]
    pub parentesco: String,
    
    #[schemars(description = "Situación que motiva la necesidad de cuidado. VALORES VÁLIDOS: 'parto', 'adopcion', 'acogimiento', 'parto_multiple', 'adopcion_multiple', 'acogimiento_multiple', 'enfermedad', 'accidente'. Ejemplo: 'parto'")]
    pub situacion: String,
    
    #[schemars(description = "¿Es una familia monoparental? Acepta valores booleanos (true/false) o strings ('true'/'false'). Use exactamente: true (para familias monoparentales) o false (para familias con ambos padres). Ejemplo: true")]
    #[serde(deserialize_with = "deserialize_bool_or_string")]
    pub familia_monoparental: bool,
    
    #[schemars(description = "Número total de hijos incluyendo al recién nacido (requerido para Supuesto B - tercer hijo o más). Acepta números (3) o strings ('3'). Use números enteros. Ejemplo: 3")]
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(deserialize_with = "deserialize_f64_or_string")]
    pub numero_hijos: Option<f64>,
}

// Internal structure for the ZEN engine (nested)
#[derive(Debug, Serialize, Deserialize, PartialEq, schemars::JsonSchema)]
pub struct ExcedenciaInput {
    #[schemars(description = "Es un string que indica relación familiar con la persona que necesita cuidado. Valores válidos: padre, madre, hijo, hija, conyuge, pareja, esposo, esposa, mujer, marido")]
    pub parentesco: String,
    
    #[schemars(description = "Es un string que indica la situación que motiva la necesidad de cuidado. Valores válidos: parto, adopcion, acogimiento, parto_multiple, adopcion_multiple, acogimiento_multiple, enfermedad, accidente")]
    pub situacion: String,
    
    #[schemars(description = "Es un booleano para indicar si la familia es monoparental. Acepta valores booleanos (true/false) o strings ('true'/'false'). Valores válidos: true, false, 'true', 'false'")]
    #[serde(deserialize_with = "deserialize_bool_or_string")]
    pub familia_monoparental: bool,
    
    #[schemars(description = "Es un número que indica el número de hijos incluyendo al recién nacido si es el caso. Acepta números (4) o strings ('4'). Se expresa sin comillas. Valores válidos: número")]
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(deserialize_with = "deserialize_f64_or_string")]
    pub numero_hijos: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
pub struct ExcedenciaRequest {
    #[schemars(description = "Datos de entrada para evaluar el supuesto de ayuda para excedencia")]
    pub input: ExcedenciaInput,
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
struct ExcedenciaOutput {
    descripcion: String,
    importe_mensual: i32,
    #[serde(default)]
    requisitos_adicionales: String,
    supuesto: String,
    tiene_derecho_potencial: bool,
    #[serde(default)]
    errores: Vec<String>,
    #[serde(default)]
    advertencias: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, schemars::JsonSchema)]
pub struct ExcedenciaResponse {
    #[schemars(description = "Resultado de la evaluación")]
    pub output: ExcedenciaOutputForSchema,
    #[serde(default)]
    pub input: Option<ExcedenciaInput>,
    #[serde(default)]
    pub parentesco_valido: Option<bool>,
}

// Estructura para el schema JSON (para documentación MCP)
#[derive(Debug, Serialize, Deserialize, PartialEq, schemars::JsonSchema)]
pub struct ExcedenciaOutputForSchema {
    #[schemars(description = "Descripción del supuesto aplicable")]
    pub descripcion: String,
    
    #[schemars(description = "Importe mensual de la bonificación en euros. 725€ para Supuesto A (cuidado familiar), 500€ para otros supuestos válidos, 0€ si no califica")]
    pub importe_mensual: i32,
    
    #[schemars(description = "Descripción detallada de los requisitos adicionales que deben cumplirse")]
    #[serde(default)]
    pub requisitos_adicionales: String,
    
    #[schemars(description = "Letra del supuesto aplicable según la normativa (A, B, C, D, E) o vacío si no califica")]
    pub supuesto: String,
    
    #[schemars(description = "¿Cumple los requisitos intrínsecos para tener derecho potencial a la bonificación?")]
    pub tiene_derecho_potencial: bool,
    
    #[schemars(description = "Lista de errores o requisitos no cumplidos")]
    #[serde(default)]
    pub errores: Vec<String>,
    
    #[schemars(description = "Lista de advertencias o información adicional relevante")]
    #[serde(default)]
    pub advertencias: Vec<String>,
}

// =================== MOTOR DE DECISIÓN ===================

#[derive(Debug, Clone)]
struct ExcedenciaDecisionEngine;

impl ExcedenciaDecisionEngine {
    fn new() -> Self {
        Self
    }

    async fn evaluate_excedencia(&self, request: &ExcedenciaRequest) -> Result<ExcedenciaResponse, ExcedenciaError> {
        // Cargar la decisión desde el archivo JSON
        let decision_content: DecisionContent = 
            serde_json::from_str(include_str!("ayuda-excedencia-2025.json"))
            .map_err(ExcedenciaError::from)?;
        let engine = DecisionEngine::default();
        let decision = engine.create_decision(decision_content.into());
        
        // Convertir struct a JSON y luego a Variable
        let json_value = serde_json::to_value(request)?;
        
        match decision.evaluate(json_value.into()).await {
            Ok(result) => {
                // Convertir el resultado de Variable a Value y luego deserializar
                let result_value: serde_json::Value = result.result.into();
                let mut response: ExcedenciaResponse = serde_json::from_value(result_value)?;
                
                // Convertir ExcedenciaOutput a ExcedenciaOutputForSchema
                let internal_output: ExcedenciaOutput = serde_json::from_value(
                    serde_json::to_value(&response.output)?
                )?;
                
                response.output = ExcedenciaOutputForSchema {
                    descripcion: internal_output.descripcion,
                    importe_mensual: internal_output.importe_mensual,
                    requisitos_adicionales: internal_output.requisitos_adicionales,
                    supuesto: internal_output.supuesto,
                    tiene_derecho_potencial: internal_output.tiene_derecho_potencial,
                    errores: internal_output.errores,
                    advertencias: internal_output.advertencias,
                };
                
                Ok(response)
            },
            Err(zen_error) => {
                // Intentar extraer información de errores de validación
                if let Some(validation_errors) = Self::extract_validation_errors(&zen_error) {
                    Err(ExcedenciaError::ValidationError(validation_errors))
                } else {
                    Err(ExcedenciaError::ZenEngineError(*zen_error))
                }
            }
        }
    }
    
    // Función helper para extraer errores de validación del error de ZEN
    fn extract_validation_errors(error: &EvaluationError) -> Option<Vec<ValidationError>> {
        if let EvaluationError::NodeError(node_error) = error {
            if let Some(errors) = Self::extract_from_node_error(node_error) {
                return Some(errors);
            }
        }
        
        let error_str = format!("{:?}", error);
        Self::extract_from_error_string(&error_str)
    }
    
    fn extract_from_node_error(node_error: &NodeError) -> Option<Vec<ValidationError>> {
        let source_str = format!("{:?}", node_error.source);
        Self::extract_json_from_string(&source_str)
    }
    
    fn extract_from_error_string(error_str: &str) -> Option<Vec<ValidationError>> {
        Self::extract_json_from_string(error_str)
    }
    
    fn extract_json_from_string(text: &str) -> Option<Vec<ValidationError>> {
        let patterns = vec![
            (r#"{"source":{"errors":"#, r#""type":"Validation"}"#),
            (r#"{"errors":"#, r#""type":"Validation"}"#),
            (r#""errors":["#, r#"]"#),
        ];
        
        for (start_pattern, end_pattern) in patterns {
            if let Some(start) = text.find(start_pattern) {
                let search_from = start + start_pattern.len();
                if let Some(relative_end) = text[search_from..].find(end_pattern) {
                    let end = search_from + relative_end + end_pattern.len();
                    let json_candidate = &text[start..end];
                    
                    if let Ok(details) = serde_json::from_str::<ValidationErrorDetails>(json_candidate) {
                        return Some(details.source.errors);
                    }
                    
                    if let Some(errors) = Self::manual_extract_errors(text) {
                        return Some(errors);
                    }
                }
            }
        }
        
        Self::manual_extract_errors(text)
    }
    
    fn manual_extract_errors(text: &str) -> Option<Vec<ValidationError>> {
        if text.contains("is not one of") {
            let lines: Vec<&str> = text.split(',').collect();
            
            let mut message = String::new();
            let mut path = String::new();
            
            for line in lines {
                if line.contains("\"message\":") {
                    if let Some(start) = line.find("\"message\":\"") {
                        let msg_start = start + "\"message\":\"".len();
                        if let Some(end) = line[msg_start..].find("\"") {
                            message = line[msg_start..msg_start + end].to_string();
                        }
                    }
                }
                if line.contains("\"path\":") {
                    if let Some(start) = line.find("\"path\":\"") {
                        let path_start = start + "\"path\":\"".len();
                        if let Some(end) = line[path_start..].find("\"") {
                            path = line[path_start..path_start + end].to_string();
                        }
                    }
                }
            }
            
            if !message.is_empty() {
                if path.is_empty() {
                    path = "/input/unknown".to_string();
                }
                return Some(vec![ValidationError { message, path }]);
            }
        }
        
        None
    }
}

// =================== CALCULADORA MCP ===================

#[derive(Debug, Clone)]
pub struct Calculadora {
    tool_router: ToolRouter<Self>,
}

#[tool_router]
impl Calculadora {
    pub fn new() -> Self {
        Self {
            tool_router: Self::tool_router(),
        }
    }

    /// Evalúa el derecho a ayuda para excedencia según la normativa de Navarra 2025
    /// 
    /// IMPORTANTE: Use los valores exactos especificados en cada parámetro.
    /// 
    /// EJEMPLOS DE LLAMADAS CORRECTAS:
    /// 1. Padre soltero con recién nacido:
    ///    - parentesco: "padre"
    ///    - situacion: "parto"
    ///    - familia_monoparental: true
    ///    - numero_hijos: 1
    /// 
    /// 2. Cuidado de madre enferma (familia normal):
    ///    - parentesco: "madre"  
    ///    - situacion: "enfermedad"
    ///    - familia_monoparental: false
    ///    
    /// 3. Tercer hijo en familia normal:
    ///    - parentesco: "madre"
    ///    - situacion: "parto"
    ///    - familia_monoparental: false
    ///    - numero_hijos: 3
    #[tool(description = "Evalúa el derecho a ayuda para excedencia según la normativa de Navarra 2025. Determina supuesto (A-E) e importe (0€/500€/725€). SUPUESTOS: A=Cuidado familiar enfermo (725€), B=Tercer hijo+ (500€), C=Adopción (500€), D=Múltiple (500€), E=Monoparental (500€). USE VALORES EXACTOS: parentesco ('padre'/'madre'/'hijo'/'hija'/'conyuge'/'esposo'/'esposa'/'mujer'/'marido'), situacion ('parto'/'adopcion'/'acogimiento'/'parto_multiple'/'adopcion_multiple'/'acogimiento_multiple'/'enfermedad'/'accidente'), familia_monoparental (true/false), numero_hijos (número).")]
    pub async fn evaluar_supuesto_excedencia(
        &self, 
        Parameters(direct_params): Parameters<ExcedenciaDirectParams>
    ) -> Result<CallToolResult, McpError> {
        // Convert direct parameters to nested structure expected by the engine
        let request = ExcedenciaRequest {
            input: ExcedenciaInput {
                parentesco: direct_params.parentesco,
                situacion: direct_params.situacion,
                familia_monoparental: direct_params.familia_monoparental,
                numero_hijos: direct_params.numero_hijos,
            }
        };

        // Usar tokio::task::spawn_blocking para operaciones que no son Send
        let result = tokio::task::spawn_blocking(move || {
            // Crear un runtime tokio para la operación async dentro del bloque blocking
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async move {
                let engine = ExcedenciaDecisionEngine::new();
                engine.evaluate_excedencia(&request).await
            })
        }).await;
        
        match result {
            Ok(eval_result) => {
                match eval_result {
                    Ok(response) => {
                        // Serialize the response to JSON and return as success
                        match serde_json::to_string_pretty(&response) {
                            Ok(json_str) => Ok(CallToolResult::success(vec![Content::text(json_str)])),
                            Err(e) => Ok(CallToolResult::error(vec![Content::text(format!(
                                "Error al serializar la respuesta: {}", e
                            ))]))
                        }
                    },
                    Err(e) => {
                        let error_msg = match e {
                            ExcedenciaError::ValidationError(validation_errors) => {
                                let mut msg = "Errores de validación:\n".to_string();
                                for error in validation_errors {
                                    msg.push_str(&format!("  - Campo '{}': {}\n", error.path, error.message));
                                }
                                msg
                            },
                            _ => format!("Error al evaluar: {}", e)
                        };
                        Ok(CallToolResult::error(vec![Content::text(error_msg)]))
                    }
                }
            },
            Err(join_error) => {
                Ok(CallToolResult::error(vec![Content::text(format!(
                    "Error interno: {}", join_error
                ))]))
            }
        }
    }
}

#[tool_handler]
impl ServerHandler for Calculadora {
    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            instructions: Some(
                "Calculadora de ayudas para excedencia según la normativa de Navarra 2025. \
                 \n\n** INSTRUCCIONES IMPORTANTES PARA USO DE HERRAMIENTAS **\
                 \n\n1. SIEMPRE use los valores EXACTOS especificados para cada parámetro, CASE SENSITIVE\
                 \n\n2. Para parentesco, use ÚNICAMENTE: 'padre', 'madre', 'hijo', 'hija', 'conyuge', 'esposo', 'esposa', 'mujer', 'marido'\
                 \n\n3. Para situacion, use ÚNICAMENTE: 'parto', 'adopcion', 'acogimiento', 'parto_multiple', 'adopcion_multiple', 'acogimiento_multiple', 'enfermedad', 'accidente'\
                 \n\n4. Para familia_monoparental, use ÚNICAMENTE: true (para familias monoparentales) o false (para familias no monoparentales)\
                 \n\n5. Para numero_hijos, use números enteros (ej: 1, 2, 3, 4, 5)\
                 \n\nEJEMPLOS DE USO CORRECTO:\
                 \n• Padre soltero con bebé: parentesco='padre', situacion='parto', familia_monoparental=true, numero_hijos=1\
                 \n• Hijo cuidando a padre enfermo: parentesco='padre', situacion='enfermedad', familia_monoparental=false\
                 \n• Familia con tercer hijo: parentesco='madre', situacion='parto', familia_monoparental=false, numero_hijos=3\
                 \n\nSUPUESTOS EVALUADOS:\
                 \nA) Cuidado familiar enfermo/accidentado (725€/mes)\
                 \nB) Tercer hijo+ con recién nacido (500€/mes)\
                 \nC) Adopción/acogimiento (500€/mes)\
                 \nD) Partos/adopciones múltiples (500€/mes)\
                 \nE) Familias monoparentales (500€/mes)".into()
            ),
            capabilities: ServerCapabilities::builder().enable_tools().build(),
            server_info: rmcp::model::Implementation {
                name: "bon-calculadora".to_string(),
                version: "1.0.0".to_string(),
            },
            ..Default::default()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_calculadora_supuesto_a() {
        let calculadora = Calculadora::new();
        let direct_params = ExcedenciaDirectParams {
            parentesco: "madre".to_string(),
            situacion: "enfermedad".to_string(),
            familia_monoparental: false,
            numero_hijos: None,
        };
        
        let result = calculadora.evaluar_supuesto_excedencia(Parameters(direct_params)).await;
        match result {
            Ok(call_result) => {
                // Check if it's a success result
                println!("Resultado Supuesto A: {:?}", call_result);
            },
            Err(e) => panic!("Error inesperado: {}", e),
        }
    }

    #[tokio::test] 
    async fn test_calculadora_supuesto_e() {
        let calculadora = Calculadora::new();
        let direct_params = ExcedenciaDirectParams {
            parentesco: "madre".to_string(),
            situacion: "parto".to_string(),
            familia_monoparental: true,
            numero_hijos: Some(1.0),
        };
        
        let result = calculadora.evaluar_supuesto_excedencia(Parameters(direct_params)).await;
        match result {
            Ok(call_result) => {
                println!("Resultado Supuesto E: {:?}", call_result);
            },
            Err(e) => panic!("Error inesperado: {}", e),
        }
    }

    #[tokio::test]
    async fn test_calculadora_supuesto_b() {
        let calculadora = Calculadora::new();
        let direct_params = ExcedenciaDirectParams {
            parentesco: "madre".to_string(),
            situacion: "parto".to_string(),
            familia_monoparental: false,
            numero_hijos: Some(3.0), // Tercer hijo
        };
        
        let result = calculadora.evaluar_supuesto_excedencia(Parameters(direct_params)).await;
        match result {
            Ok(call_result) => {
                println!("Resultado Supuesto B: {:?}", call_result);
            },
            Err(e) => panic!("Error inesperado: {}", e),
        }
    }

    #[tokio::test]
    async fn test_calculadora_validation_error() {
        let calculadora = Calculadora::new();
        let direct_params = ExcedenciaDirectParams {
            parentesco: "hermano".to_string(), // No válido
            situacion: "parto".to_string(),
            familia_monoparental: false,
            numero_hijos: None,
        };
        
        let result = calculadora.evaluar_supuesto_excedencia(Parameters(direct_params)).await;
        match result {
            Ok(call_result) => {
                // Should handle validation errors appropriately
                println!("Validation result: {:?}", call_result);
            },
            Err(e) => panic!("Error inesperado: {}", e),
        }
    }
}