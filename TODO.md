# TODO - Entrega Final TPE Redes
**Fecha límite:** Miércoles 5 de Noviembre, 23:59hs
**Presentación:** Jueves 6 o Martes 11 de Noviembre

---

## 🔴 CRÍTICO - Implementación Código

### 1. Integrar rol `common` en el flujo de despliegue
- [ ] **Tarea:** Modificar `ansible/playbooks/deploy-all.yml` para ejecutar el rol common en todos los nodos
- [ ] **Ubicación:** Agregar nuevo play ANTES de `control-plane.yml`
- [ ] **Contenido del play:**
  ```yaml
  - name: Prepare all nodes with common configuration
    hosts: all
    become: true
    roles:
      - common
  ```
- [ ] **Verificar:** El rol common ya existe en `ansible/roles/common/tasks/main.yml`
- [ ] **Validar:** Ejecutar `deploy-all.yml` desde cero y verificar que actualiza los nodos
- **Tiempo estimado:** 30 minutos
- **Archivos:** `ansible/playbooks/deploy-all.yml`

---

### 2. Arreglar completamente `scale.yml`
#### 2.1 Actualizar inventory automáticamente después de crear VMs
- [ ] **Agregar task:** Obtener IPs de las nuevas VMs (similar a `provision.yml` líneas 32-46)
- [ ] **Agregar task:** Actualizar `ansible/inventory.yml` con los nuevos workers
- [ ] **Agregar task:** Refrescar inventory en memoria
  ```yaml
  - name: Refresh inventory
    meta: refresh_inventory
  ```

#### 2.2 Ejecutar configuración completa en nuevos nodos
- [ ] **Modificar:** El play que ejecuta el rol worker debe incluir también el rol common
- [ ] **Cambiar líneas 64-71** de `scale.yml` a:
  ```yaml
  - name: Configure new worker nodes
    hosts: workers
    become: true
    gather_facts: true
    tasks:
      - name: Only configure newly added nodes
        block:
          - import_role:
              name: common
          - import_role:
              name: worker
        when: inventory_hostname not in groups['workers'][:existing_worker_count|int]
  ```

#### 2.3 Validar que los nodos se unieron correctamente
- [ ] **Agregar play final:** Verificar que los nuevos nodos aparecen como Ready
  ```yaml
  - name: Verify new nodes joined
    hosts: master
    tasks:
      - name: Get cluster nodes
        command: kubectl get nodes
        register: nodes
      - name: Display nodes
        debug:
          msg: "{{ nodes.stdout_lines }}"
  ```

- **Tiempo estimado:** 2 horas
- **Archivos:** `ansible/playbooks/scale.yml`, `ansible/inventory.yml`
- **Testing:** Probar agregando 1 worker, verificar que aparece en inventory y en cluster

---

### 3. Preparar despliegue de aplicación "The Store"

#### 3.1 Obtener/Crear manifests de k3s
- [ ] **Opción A:** Si tienen manifests de The Store, copiarlos a `k8s-manifests/the-store/`
- [ ] **Opción B:** Crear manifests simples de demo en `k8s-manifests/demo-app/`:
  - [ ] `frontend-deployment.yaml` (nginx)
  - [ ] `frontend-service.yaml` (NodePort o LoadBalancer)
  - [ ] `backend-deployment.yaml` (API simple)
  - [ ] `backend-service.yaml` (ClusterIP)
  - [ ] `redis-deployment.yaml`
  - [ ] `redis-service.yaml`
- **Tiempo estimado:** 1.5 horas
- **Archivos:** Nueva carpeta `k8s-manifests/`

#### 3.2 Crear playbook `deploy-app.yml`
- [ ] **Crear:** `ansible/playbooks/deploy-app.yml`
- [ ] **Estructura básica:**
  ```yaml
  ---
  - name: Deploy application to k3s cluster
    hosts: master
    become: true

    vars:
      manifests_dir: "../../k8s-manifests/demo-app"
      remote_manifests_dir: "/tmp/k8s-manifests"

    tasks:
      - name: Create remote manifests directory
        file:
          path: "{{ remote_manifests_dir }}"
          state: directory

      - name: Copy manifests to master node
        copy:
          src: "{{ manifests_dir }}/"
          dest: "{{ remote_manifests_dir }}/"

      - name: Apply all manifests
        command: kubectl apply -f {{ remote_manifests_dir }}/
        environment:
          KUBECONFIG: /etc/rancher/k3s/k3s.yaml

      - name: Wait for pods to be ready
        command: kubectl wait --for=condition=Ready pods --all --timeout=300s
        environment:
          KUBECONFIG: /etc/rancher/k3s/k3s.yaml

      - name: Get deployed pods
        command: kubectl get pods -o wide
        register: pods
        environment:
          KUBECONFIG: /etc/rancher/k3s/k3s.yaml

      - name: Display pods
        debug:
          msg: "{{ pods.stdout_lines }}"

      - name: Get services
        command: kubectl get services
        register: services
        environment:
          KUBECONFIG: /etc/rancher/k3s/k3s.yaml

      - name: Display services with access info
        debug:
          msg: "{{ services.stdout_lines }}"
  ```
- [ ] **Testing:** Ejecutar playbook y verificar que los pods corren
- **Tiempo estimado:** 45 minutos
- **Archivos:** `ansible/playbooks/deploy-app.yml`

---

### 4. Verificar que las IPs coinciden con el informe
- [ ] **Revisar:** El PoC menciona IPs 192.168.64.10, .11, .12
- [ ] **Estado actual:** Cluster usa 192.168.64.14, .15, .16
- [ ] **Decisión:** ¿Actualizar el informe o cambiar las IPs de las VMs?
- [ ] **Si cambian IPs:** Destruir y recrear VMs con IPs específicas usando cloud-init
- [ ] **Si actualizan doc:** Ya está hecho en README.md, solo falta el PoC final
- **Tiempo estimado:** Depende de la decisión (0-2 horas)

---

## 🟡 ALTA PRIORIDAD - Documentación

### 5. Documento de integración con Terraform (teórica)
- [ ] **Crear:** `docs/integracion-terraform.md`
- [ ] **Secciones a incluir:**
  - [ ] Introducción: ¿Por qué integrar Terraform con Ansible?
  - [ ] Arquitectura propuesta
    - Terraform provisiona infraestructura (VMs en AWS/Azure/GCP)
    - Ansible configura y gestiona k3s cluster
  - [ ] Flujo de trabajo:
    ```
    1. terraform apply → Crea VMs en cloud
    2. terraform output → Genera IPs y datos de VMs
    3. Ansible dynamic inventory → Lee outputs de Terraform
    4. ansible-playbook deploy-all.yml → Instala k3s cluster
    ```
  - [ ] Ejemplo de Terraform output:
    ```hcl
    output "master_ip" {
      value = aws_instance.k3s_master.public_ip
    }
    output "worker_ips" {
      value = aws_instance.k3s_workers[*].public_ip
    }
    ```
  - [ ] Ejemplo de dynamic inventory (teórico):
    - Script Python que lee `terraform output -json`
    - Genera formato de inventory de Ansible
  - [ ] Ventajas de esta integración:
    - Infraestructura como código completa
    - Reproducibilidad total
    - Escalabilidad cloud
    - Separación de responsabilidades (infra vs config)
  - [ ] Diagrama de integración (puede ser ASCII art o referencia a crear uno)
- **Tiempo estimado:** 1 hora
- **Archivos:** `docs/integracion-terraform.md`

---

### 6. Expandir README como How-To completo
- [ ] **Modificar:** `README.md` en la raíz del proyecto
- [ ] **Agregar/Expandir secciones:**

#### 6.1 Prerequisites (más detallado)
- [ ] Versiones exactas de software requerido
- [ ] Comandos de instalación para diferentes OS
- [ ] Verificación de instalación correcta

#### 6.2 Setup paso a paso con outputs esperados
- [ ] **Paso 1:** Clonar repositorio
- [ ] **Paso 2:** Configurar SSH keys (copiar el comando exacto)
- [ ] **Paso 3:** Crear VMs con `test_cluster.sh create`
  - [ ] Output esperado del comando
  - [ ] Cómo verificar que las VMs están corriendo (`multipass list`)
- [ ] **Paso 4:** Verificar conectividad Ansible
  - [ ] `cd ansible && ansible all -m ping`
  - [ ] Output esperado (todos con pong)
- [ ] **Paso 5:** Desplegar cluster
  - [ ] `ansible-playbook playbooks/deploy-all.yml`
  - [ ] Output esperado (resumen final con 3 nodos Ready)
- [ ] **Paso 6:** Verificar estado
  - [ ] `ansible-playbook playbooks/status.yml`
  - [ ] Explicar el output

#### 6.3 Casos de uso comunes
- [ ] **Escalar el cluster:**
  - Comando completo
  - Qué esperar
  - Cómo verificar
- [ ] **Desplegar aplicación:**
  - `ansible-playbook playbooks/deploy-app.yml`
  - Cómo acceder a la aplicación desplegada
- [ ] **Ver logs de un servicio:**
  - Usando Ansible para ejecutar comandos en nodos
- [ ] **Desinstalar el cluster:**
  - `ansible-playbook playbooks/uninstall.yml`
  - Cleanup completo

#### 6.4 Troubleshooting expandido
- [ ] **Problema:** VMs no arrancan
  - Causas posibles
  - Soluciones paso a paso
- [ ] **Problema:** Ansible no puede conectarse
  - Verificar SSH keys
  - Verificar inventory IPs
  - Comandos de debug
- [ ] **Problema:** Master no inicia k3s
  - Ver logs: `multipass exec k3s-master -- sudo journalctl -u k3s`
  - Causas comunes (firewall, recursos insuficientes)
- [ ] **Problema:** Workers no se unen al cluster
  - Verificar token
  - Verificar conectividad master:6443
  - Comandos de debug
- [ ] **Problema:** Pods no arrancan
  - `kubectl describe pod`
  - Revisar eventos
  - Verificar recursos

#### 6.5 Arquitectura detallada
- [ ] Diagrama de red con IPs específicas
- [ ] Componentes de k3s en cada nodo
- [ ] Flujo de datos entre componentes

- **Tiempo estimado:** 2-2.5 horas
- **Archivos:** `README.md`

---

### 7. Actualizar `docs/arquitectura.md`
- [ ] **Verificar/Actualizar IPs:**
  - [ ] Deben coincidir con el PoC (192.168.64.10-12) o documentar las actuales
  - [ ] Actualizar todos los diagramas
- [ ] **Agregar sección:** "Integración con Terraform"
  - [ ] Referencia a `integracion-terraform.md`
  - [ ] Diagrama de alto nivel
- [ ] **Detallar red de k3s:**
  - [ ] Red de host: 192.168.64.0/24
  - [ ] Red de pods: 10.42.0.0/16 (Flannel)
  - [ ] Red de services: 10.43.0.0/16
  - [ ] Cómo se comunican entre sí
- [ ] **Explicar componentes de k3s:**
  - [ ] Control plane: API Server, Scheduler, Controller, etcd
  - [ ] Workers: kubelet, kube-proxy, containerd
  - [ ] CNI: Flannel (incluido en k3s)
- **Tiempo estimado:** 30-45 minutos
- **Archivos:** `docs/arquitectura.md`

---

### 8. Actualizar documento PoC final
- [ ] **Revisar:** `docs/PoC.pdf` original de la pre-entrega
- [ ] **Crear:** Versión actualizada con lo implementado
- [ ] **Secciones a actualizar:**
  - [ ] IPs reales utilizadas
  - [ ] Playbooks finales (agregar deploy-app.yml)
  - [ ] Integración con Terraform (nueva sección)
  - [ ] Capturas de pantalla del cluster funcionando
  - [ ] Aplicación desplegada (The Store o demo)
- **Tiempo estimado:** 1 hora
- **Archivos:** `docs/PoC-Final.pdf`

---

## 🟢 PRESENTACIÓN Y ENTREGA

### 9. Preparar presentación PPT
- [ ] **Crear:** `presentacion/TPE-Redes-Ansible.pptx`
- [ ] **Estructura (máximo 30 minutos):**

#### Slide 1: Portada
- [ ] Título: "Gestión de Cluster Kubernetes con Ansible"
- [ ] Subtítulo: "TPE Redes de Información 2C 2025"
- [ ] Integrantes y legajos

#### Slides 2-3: Introducción a Ansible
- [ ] ¿Qué es Ansible?
- [ ] ¿Por qué Ansible para gestionar k3s?
- [ ] Ventajas vs gestión manual (kubectl)

#### Slides 4-6: Arquitectura implementada
- [ ] Diagrama de red completo
- [ ] Componentes: Control plane + Workers
- [ ] k3s vs k8s: ¿Por qué k3s?
- [ ] Tecnologías: Multipass, Ubuntu 22.04, Flannel CNI

#### Slides 7-9: Playbooks y Roles
- [ ] Estructura del proyecto
- [ ] Roles: common, master, worker
- [ ] Playbooks principales:
  - deploy-all.yml: Instalación completa
  - scale.yml: Escalamiento
  - status.yml: Monitoreo
  - deploy-app.yml: Despliegue de aplicaciones
  - uninstall.yml: Limpieza

#### Slide 10: Integración con Terraform
- [ ] Diagrama de integración
- [ ] Flujo: Terraform → Ansible
- [ ] Ventajas de la integración
- [ ] Escalabilidad a cloud

#### Slides 11-13: DEMO EN VIVO (script detallado)
- [ ] **Demo 1:** Cluster funcionando
  - Ejecutar `status.yml`
  - Mostrar 3 nodos Ready
  - Mostrar pods del sistema (CoreDNS, Traefik, etc)
- [ ] **Demo 2:** Escalamiento
  - Ejecutar `scale.yml` para agregar 1 worker
  - Mostrar cómo se crea la VM
  - Mostrar cómo se actualiza el inventory
  - Verificar nuevo nodo en cluster (4 nodos)
- [ ] **Demo 3:** Despliegue de aplicación
  - Ejecutar `deploy-app.yml`
  - Mostrar pods de la aplicación corriendo
  - Acceder a la aplicación (si es posible mostrar en browser)

#### Slide 14: Características implementadas
- [ ] ✅ Provisión automatizada de VMs
- [ ] ✅ Instalación completa de k3s cluster
- [ ] ✅ Escalamiento dinámico (add/remove workers)
- [ ] ✅ Monitoreo de estado
- [ ] ✅ Despliegue de aplicaciones
- [ ] ✅ Idempotencia de playbooks
- [ ] ✅ Documentación completa
- [ ] ✅ Integración teórica con Terraform

#### Slide 15: Aprendizajes y desafíos
- [ ] Desafíos técnicos encontrados
- [ ] Soluciones implementadas
- [ ] Aprendizajes del equipo

#### Slide 16: Trabajo futuro
- [ ] Migración a cloud (AWS/Azure)
- [ ] Integración real con Terraform
- [ ] CI/CD para actualizaciones
- [ ] Monitoreo avanzado (Prometheus/Grafana)
- [ ] Alta disponibilidad (múltiples masters)

#### Slide 17: Conclusiones
- [ ] Resumen de objetivos cumplidos
- [ ] Ansible como herramienta poderosa para IaC
- [ ] k3s como alternativa ligera de Kubernetes

#### Slide 18: Q&A
- [ ] Preguntas frecuentes preparadas
- [ ] Contacto del equipo

- [ ] **Preparar script de presentación:** Quién dice qué (dividir entre los 3)
- [ ] **Ensayar timing:** No pasar de 30 minutos
- [ ] **Backup plan:** Tener grabación de la demo por si falla en vivo

- **Tiempo estimado:** 2.5-3 horas
- **Archivos:** `presentacion/TPE-Redes-Ansible.pptx`, `presentacion/script-presentacion.md`

---

### 10. Testing completo del sistema
- [ ] **Test 1:** Instalación desde cero
  - [ ] Destruir cluster actual: `scripts/test_cluster.sh destroy`
  - [ ] Crear nuevas VMs: `scripts/test_cluster.sh create`
  - [ ] Ejecutar deploy-all.yml
  - [ ] Verificar que todo funciona
  - [ ] Documentar tiempo total de instalación

- [ ] **Test 2:** Scaling up
  - [ ] Ejecutar scale.yml para agregar 1 worker
  - [ ] Verificar que aparece en inventory
  - [ ] Verificar que aparece en cluster
  - [ ] Verificar que puede ejecutar pods

- [ ] **Test 3:** Despliegue de aplicación
  - [ ] Ejecutar deploy-app.yml
  - [ ] Verificar que todos los pods están Ready
  - [ ] Verificar conectividad entre servicios
  - [ ] Probar acceso externo (si aplica)

- [ ] **Test 4:** Status y monitoreo
  - [ ] Ejecutar status.yml
  - [ ] Verificar que muestra información correcta
  - [ ] Probar en diferentes estados del cluster

- [ ] **Test 5:** Scaling down
  - [ ] Ejecutar scale.yml para remover 1 worker
  - [ ] Verificar que se remueve del inventory
  - [ ] Verificar que los pods se redistribuyen

- [ ] **Test 6:** Uninstall completo
  - [ ] Ejecutar uninstall.yml
  - [ ] Verificar que k3s se desinstala de todos los nodos
  - [ ] Verificar que las VMs quedan limpias

- [ ] **Test 7:** Idempotencia
  - [ ] Ejecutar deploy-all.yml sobre cluster existente
  - [ ] Verificar que no rompe nada
  - [ ] Verificar que detecta que ya está instalado

- **Tiempo estimado:** 2 horas
- **Documentar resultados:** Crear `docs/test-results.md` con screenshots

---

## 📋 VERIFICACIÓN PRE-ENTREGA

### Checklist final antes de subir a Campus
- [ ] **Código:**
  - [ ] Todos los playbooks funcionan sin errores
  - [ ] Los roles están completos y se usan correctamente
  - [ ] El scaling funciona completamente (add y remove)
  - [ ] La aplicación de demo se despliega correctamente
  - [ ] No hay código comentado o debug prints innecesarios
  - [ ] Las variables están bien documentadas

- [ ] **Documentación:**
  - [ ] README.md completo y actualizado
  - [ ] docs/arquitectura.md actualizado con IPs correctas
  - [ ] docs/integracion-terraform.md creado
  - [ ] docs/PoC-Final.pdf actualizado
  - [ ] Todos los comandos en docs tienen output esperado
  - [ ] Troubleshooting cubre casos comunes

- [ ] **Presentación:**
  - [ ] PPT completa (máximo 30 min)
  - [ ] Script de presentación escrito y dividido entre integrantes
  - [ ] Demo ensayada y funcionando
  - [ ] Backup de la demo (grabación o screenshots)
  - [ ] Preguntas frecuentes preparadas

- [ ] **Material para subir a Campus:**
  - [ ] Presentación PPT
  - [ ] Documento final (PoC actualizado)
  - [ ] Link al repositorio GitHub (debe ser público o dar acceso)
  - [ ] README en GitHub funciona como How-To completo

- [ ] **GitHub:**
  - [ ] Repositorio limpio y organizado
  - [ ] README.md es la cara pública del proyecto
  - [ ] .gitignore configurado (no subir tokens, logs, etc)
  - [ ] Commits con mensajes descriptivos
  - [ ] Tags/releases para la entrega final

- [ ] **Preparación equipo:**
  - [ ] Los 3 integrantes saben explicar cualquier parte
  - [ ] Cada uno tiene su parte de la presentación preparada
  - [ ] Todos pueden responder preguntas técnicas
  - [ ] Entorno de demo testeado en la máquina de presentación

---

## 📅 Timeline Sugerido

### Semana 1 (28 Oct - 3 Nov)
- **Lunes-Martes:** Implementación código (puntos 1-4)
- **Miércoles-Jueves:** Documentación técnica (puntos 5-7)
- **Viernes:** Actualizar PoC final (punto 8)

### Semana 2 (4-5 Nov)
- **Lunes:** Preparar presentación PPT (punto 9)
- **Martes:** Testing completo (punto 10)
- **Miércoles 5 Nov:**
  - Mañana: Verificación pre-entrega y ajustes finales
  - Tarde: Subir material a Campus antes de las 23:59hs

### Post-entrega (6-11 Nov)
- **6 o 11 Nov:** Presentación oral (30 min máximo)
- Ensayar la presentación al menos 2 veces antes

---

## ⏱️ Resumen de tiempo estimado total

| Categoría | Tiempo |
|-----------|--------|
| Implementación código | 5-6 horas |
| Documentación técnica | 4-5 horas |
| Presentación PPT | 3 horas |
| Testing y ajustes | 2-3 horas |
| **TOTAL** | **14-17 horas** |

Distribuido entre 3 personas: ~5-6 horas por persona

---

## 💡 Tips importantes

1. **Git commits frecuentes:** Hacer commits pequeños y descriptivos
2. **Testing continuo:** No esperar al final para probar todo
3. **Dividir trabajo:** Cada uno toma responsabilidad de secciones específicas
4. **Comunicación:** Usar issues de GitHub o chat para coordinar
5. **Backup:** Guardar copias de la presentación y demos
6. **Tiempo:** No dejar todo para el último día
7. **Preguntas:** Si algo no está claro, preguntar a la cátedra con anticipación

---

## 🚨 Recordatorios críticos

- ⚠️ La entrega debe cumplir **AL 100%** con lo prometido en la pre-entrega
- ⚠️ No cumplir = recuperatorio del TPE
- ⚠️ Los 3 integrantes deben estar presentes en la presentación
- ⚠️ La presentación es online y remota (verificar conexión/cámara/micrófono)
- ⚠️ Máximo 30 minutos de presentación

---

**Última actualización:** 26 de Octubre 2025
