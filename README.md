# Portafolio Actuarial — Proyecto 05
## Reconciliación Transaccional y Cálculo de Prima Devengada

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=flat&logo=postgresql&logoColor=white)
![SQL](https://img.shields.io/badge/SQL-003B57?style=flat&logo=postgresql&logoColor=white)
![Área](https://img.shields.io/badge/Área-Análisis%20Actuarial-1B3A6B?style=flat)
![Escala](https://img.shields.io/badge/Escala-1,000,000%20Pólizas-2E6DB4?style=flat)

---

## ¿De qué trata este proyecto?

Este modelo ejecuta la **reconciliación de datos masivos transaccionales** y calcula el devengamiento histórico de primas en un portafolio de seguros. El procesamiento se realiza íntegramente en el motor relacional **PostgreSQL**, estructurando el código a través de **Positron IDE**.

El objetivo del proyecto es doble: demostrar rigurosidad matemática en el cálculo actuarial de exposición al riesgo y certificar competencias de ingeniería de datos al optimizar consultas (DQL) sobre un volumen sintético de más de un millón de registros, exigencia habitual en las evaluaciones técnicas corporativas del sector asegurador.

---

## Técnicas y algoritmos implementados

| Concepto Técnico | Herramienta SQL | Justificación Actuarial |
|---|---|---|
| Aislamiento Lógico | CTEs (`WITH`) | Estructurar el estado financiero paso a paso sin colapsar la memoria |
| Iteración Temporal | Window Functions | Calcular primas acumuladas y aislar el último estado sin subconsultas |
| Optimización B-Tree | Índices y `ANALYZE` | Reducir la complejidad de búsqueda y evitar escaneos secuenciales masivos |
| Cruce Referencial | `INNER JOIN` / `LEFT JOIN` | Garantizar que los siniestros contabilizados ocurran dentro de vigencia |

---

## Fundamento teórico

El modelo implementa dos principios fundamentales del análisis actuarial y control de reservas:

### 1. Devengamiento Pro Rata Temporis
El cálculo de la prima devengada asume un reconocimiento lineal del riesgo bajo una base diaria. Para una póliza $i$ con $m$ endosos transaccionales evaluada al tiempo $t$:

$$Prima\_Devengada_{i}(t) = \sum_{k=1}^{m} P_{i,k} \times \left( \frac{\max(0, \min(t, F\_fin_{i,k}) - F\_inicio_{i,k})}{F\_fin_{i,k} - F\_inicio_{i,k}} \right)$$

### 2. Consistencia Referencial de Siniestros
Para evitar el pago o la reserva de siniestros extemporáneos, toda reclamación $S_j$ vinculada a la póliza $i$ debe cumplir la siguiente desigualdad respecto a su fecha de ocurrencia $T(S_j)$:

$$F\_emision_{i} \leq T(S_j) \leq F\_cancelacion_{i}$$

---

## Estructura del repositorio

```text
Proyecto05_SQL_Positron/
│
├── proyecto_reconciliacion_actuarial.sql   # Código DDL, DML y DQL estructurado
├── Proyecto05_SQL_Reconciliacion.pdf       # Documento teórico compilado
└── README.md
