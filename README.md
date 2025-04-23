# ⚙️ microservice-app-ops

Este repositorio contiene la automatización de la infraestructura necesaria para desplegar la aplicación **MicroTodoSuite** en Azure. Aquí se definen y gestionan todos los recursos en la nube mediante **Terraform**, garantizando un aprovisionamiento reproducible, controlado y versionado como código.

## 📁 Estructura del Repositorio

```
microservice-app-ops/
├── .github/workflows/     # Pipelines de GitHub Actions (deploy y destroy)
├── terraform/             # Infraestructura como código (IaC)
└── README.md              # Este archivo
```

## 🚀 Pipelines Disponibles

El flujo de trabajo del equipo de operaciones está respaldado por dos pipelines automatizados que se ejecutan mediante **GitHub Actions**:

- **Pipeline de Despliegue (`deploy`):**  
  Ejecuta el aprovisionamiento completo de la infraestructura realizada con Terraform en Azure, permitiendo crear los servicios necesarios para el despliegue de los microservicios.

- **Pipeline de Destrucción (`destroy`):**  
  Elimina todos los recursos definidos en el código Terraform, permitiendo limpiar completamente el entorno de manera controlada.

## 🛠️ Herramienta de Infraestructura como Código

Utilizamos **Terraform** como herramienta principal para definir y aplicar la infraestructura. La solución está dividida por módulos reutilizables y configuraciones por entorno.

## 🌱 Estrategia de Branching

Este repositorio adopta el enfoque de **Trunk-Based Development**, lo cual significa que:

- Todo el trabajo se realiza en ramas de corta vida que se integran rápidamente a `main`.
- Los cambios se prueban y despliegan de forma continua a través de pipelines automatizados.
- Se busca mantener siempre la rama principal (`main`) en estado estable y desplegable.
