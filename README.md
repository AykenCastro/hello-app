# Projeto com Tutorial Completo: CI/CD com GitHub Actions e ArgoCD

Este tutorial guiará você na criação de um pipeline completo de CI/CD (Integração Contínua e Entrega Contínua) utilizando GitHub Actions e ArgoCD.

## 📋 Visão Geral

### Arquitetura do Sistema

O projeto utiliza uma estratégia de **dois repositórios**:

- **🚀 hello-app**: Repositório da aplicação (código fonte)
- **📁 hello-manifests**: Repositório de manifestos Kubernetes (configurações de deploy)

### Fluxo do Pipeline

1. **CI (Integração Contínua)**: Push no código → GitHub Actions testa, constrói imagem Docker e envia para Docker Hub
2. **CD (Entrega Contínua)**: GitHub Actions atualiza manifestos → ArgoCD detecta mudanças → Aplicação é atualizada no cluster Kubernetes

## ⚙️ Pré-requisitos

- ✅ Conta no [GitHub](https://github.com)
- ✅ Conta no [Docker Hub](https://hub.docker.com)
- ✅ [Rancher Desktop](https://rancherdesktop.io/) instalado (ou outro cluster Kubernetes)
- ✅ [ArgoCD](https://argo-cd.readthedocs.io/) instalado no cluster
- ✅ Conhecimento básico de Git, Docker e Kubernetes

## 🏗️ Estrutura dos Repositórios

### Repositório 1: hello-app (Aplicação)
```
hello-app/
├── .github/
│   └── workflows/
│       └── ci-cd.yml
├── main.py
├── Dockerfile
└── requirements.txt
```

### Repositório 2: hello-manifests (Manifestos Kubernetes)
```
hello-manifests/
├── deployment.yaml
└── service.yaml
```

## 📝 Etapa 1: Criar o Repositório da Aplicação (hello-app)

### 1.1 Criar e Clonar o Repositório

```bash
# No GitHub, crie um novo repositório público chamado "hello-app"
git clone https://github.com/<SEU-USUARIO>/hello-app.git
cd hello-app
```

### 1.2 Criar o Arquivo da Aplicação

Crie o arquivo `main.py`:

```python
# main.py
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
async def root():
    return {"message": "Hello World"}
```

### 1.3 Criar o Dockerfile

Crie o arquivo `Dockerfile` (sem extensão):

```dockerfile
# Dockerfile

# 1. Base Image
FROM python:3.9-slim

# 2. Set working directory
WORKDIR /app

# 3. Install dependencies
COPY requirements.txt .
RUN pip install fastapi uvicorn

# 4. Copy app code
COPY . .

# 5. Expose port and run
EXPOSE 80
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "80"]
```

### 1.4 Criar requirements.txt

Crie um arquivo `requirements.txt` vazio (por enquanto):

```txt
# Arquivo vazio - as dependências são instaladas diretamente no Dockerfile
```

### 1.5 Primeiro Commit

```bash
git add .
git commit -m "Versão inicial da hello-app"
git push origin main
```

## 📝 Etapa 2: Criar o Repositório de Manifestos (hello-manifests)

### 2.1 Criar e Clonar o Repositório

```bash
# Em uma pasta DIFERENTE da 'hello-app'
git clone https://github.com/<SEU-USUARIO>/hello-manifests.git
cd hello-manifests
```

### 2.2 Criar deployment.yaml

Crie o arquivo `deployment.yaml`:

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hello-app
  template:
    metadata:
      labels:
        app: hello-app
    spec:
      containers:
      - name: hello-app
        # ATENÇÃO: Substitua <SEU-DOCKERHUB-USERNAME> pelo seu usuário!
        image: <SEU-DOCKERHUB-USERNAME>/hello-app:initial
        ports:
        - containerPort: 80
```

### 2.3 Criar service.yaml

Crie o arquivo `service.yaml`:

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-app-service
spec:
  type: ClusterIP
  selector:
    app: hello-app
  ports:
  - port: 8080
    targetPort: 80
```

### 2.4 Primeiro Commit dos Manifestos

```bash
git add .
git commit -m "Manifestos iniciais da hello-app"
git push origin main
```

## 🔐 Etapa 3: Configurar Segredos no GitHub

### 3.1 Acessar Configurações de Segredos

No repositório `hello-app` no GitHub:
- Vá em **Settings** → **Secrets and variables** → **Actions**
- Clique em **New repository secret**

### 3.2 Configurar Segredos do Docker Hub

#### DOCKER_USERNAME
- **Name**: `DOCKER_USERNAME`
- **Secret**: Seu nome de usuário do Docker Hub

#### DOCKER_PASSWORD
- **Name**: `DOCKER_PASSWORD`
- **Secret**: Crie um access token no Docker Hub:
  1. Acesse [Docker Hub](https://hub.docker.com)
  2. Vá em **Account Settings** → **Security** → **New Access Token**
  3. Crie um token e use-o como senha

### 3.3 Configurar Chave SSH para Deploy

#### 3.3.1 Gerar Par de Chaves SSH

```bash
ssh-keygen -t rsa -b 4096 -C "github-action-deploy" -f deploy_key -N ""
```

Isso criará dois arquivos:
- `deploy_key` (chave privada)
- `deploy_key.pub` (chave pública)

#### 3.3.2 Adicionar Chave Pública como Deploy Key

No repositório `hello-manifests`:
- Vá em **Settings** → **Deploy keys** → **Add deploy key**
- **Title**: `GitHub Action`
- **Key**: Cole o conteúdo do arquivo `deploy_key.pub`
- **✓ Marque**: *Allow write access*
- Clique em **Add key**

#### 3.3.3 Adicionar Chave Privada como Secret

No repositório `hello-app`:
- Vá em **Settings** → **Secrets and variables** → **Actions**
- **New repository secret**:
  - **Name**: `SSH_PRIVATE_KEY`
  - **Secret**: Cole o conteúdo do arquivo `deploy_key`

## ⚡ Etapa 4: Criar o GitHub Action

### 4.1 Estrutura de Diretórios

No repositório `hello-app`, crie a estrutura:

```bash
mkdir -p .github/workflows
```

### 4.2 Criar Arquivo do Workflow

Crie o arquivo `.github/workflows/ci-cd.yml`:

```yaml
# .github/workflows/ci-cd.yml
name: CI/CD Pipeline

on:
  push:
    branches: [ main ]

jobs:
  # --- JOB 1: BUILD & PUSH (CI) ---
  build-and-push-docker:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout código da app
        uses: actions/checkout@v3

      - name: Login no Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Setup Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Build e Push para Docker Hub
        uses: docker/build-push-action@v4
        with:
          context: .
          file: ./Dockerfile
          push: true
          tags: ${{ secrets.DOCKER_USERNAME }}/hello-app:${{ github.sha }}

  # --- JOB 2: UPDATE MANIFESTS (CD/GitOps) ---
  update-manifests:
    runs-on: ubuntu-latest
    needs: build-and-push-docker

    steps:
      - name: Configurar SSH para Git
        uses: webfactory/ssh-agent@v0.5.3
        with:
          ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}

      - name: Checkout repositório de manifestos
        uses: actions/checkout@v3
        with:
          # ATENÇÃO: Substitua <SEU-USUARIO> pelo seu usuário GitHub!
          repository: <SEU-USUARIO>/hello-manifests
          ssh-key: ${{ secrets.SSH_PRIVATE_KEY }}
          path: manifests

      - name: Atualizar a tag da imagem no deployment.yaml
        run: |
          sed -i 's|image:.*|image: ${{ secrets.DOCKER_USERNAME }}/hello-app:${{ github.sha }}|' manifests/deployment.yaml
      
      - name: Fazer commit e push da mudança
        run: |
          cd manifests
          git config --global user.name "GitHub Action Bot"
          git config --global user.email "bot@github.com"
          git commit -am "Atualiza tag da imagem para ${{ github.sha }}"
          git push
```

**Importante**: Substitua `<SEU-USUARIO>` pelo seu nome de usuário do GitHub.

### 4.3 Commit do Workflow

```bash
git add .github/workflows/ci-cd.yml
git commit -m "Adiciona pipeline de CI/CD"
git push origin main
```

**🎉 Este push irá disparar o primeiro pipeline!**

## 🔄 Etapa 5: Configurar o ArgoCD

### 5.1 Acessar o ArgoCD

Se o ArgoCD estiver rodando localmente:

```bash
 port-forward -n argocd svc/argocd-server 8080:443
```

Acesse: https://localhost:8080

### 5.2 Criar Nova Aplicação

1. Clique em **"+ NEW APP"**
2. Preencha os campos:

**GENERAL**:
- **Application Name**: `hello-app`
- **Project Name**: `default`
- **Sync Policy**: `Automatic`

**SOURCE**:
- **Repository URL**: `https://github.com/<SEU-USUARIO>/hello-manifests.git`
- **Path**: `.`

**DESTINATION**:
- **Cluster URL**: `https://kubernetes.default.svc`
- **Namespace**: `default`

3. Clique em **CREATE**
<img width="1920" height="944" alt="print 8" src="https://github.com/user-attachments/assets/ae0467d6-b2d1-4267-a11b-56731ef592c7" />
<img width="1919" height="964" alt="print 9" src="https://github.com/user-attachments/assets/100bffee-5b73-4d7c-a30c-01e345a58874" />


### 5.3 Sincronizar Aplicação

- Na lista de aplicações, clique em `hello-app`
- Clique em **SYNC**
- Confirme a sincronização
<img width="1920" height="953" alt="print 21" src="https://github.com/user-attachments/assets/4f7421d6-ee93-4c42-8f02-cdf323d87d98" />


## 🧪 Etapa 6: Testar o Pipeline Completo

### 6.1 Teste Inicial da Aplicação

```bash
# Fazer port-forward para o serviço
 port-forward service/hello-app-service 8081:8080
```

Acesse http://localhost:8081 no navegador ou use:

```bash
curl http://localhost:8081
```

Deve retornar: `{"message": "Hello World"}`
<img width="519" height="155" alt="print 3" src="https://github.com/user-attachments/assets/b541cb3e-be0a-4e80-9e02-4397165c3780" />


### 6.2 Testar o Loop de CI/CD

#### Modificar o Código

Edite `main.py` no repositório `hello-app`:

```python
# main.py
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
async def root():
    return {"message": "Meu pipeline de CI/CD funcionou!"}
```

#### Fazer Commit e Push

```bash
git add main.py
git commit -m "Testando o pipeline"
git push origin main
```

### 6.3 Monitorar o Processo

1. **📊 GitHub Actions**: 
   - Vá em `hello-app` → **Actions**
   - Observe o pipeline em execução

2. **🐳 Docker Hub**:
   - Verifique se uma nova imagem foi criada com o hash do commit

3. **📁 Repositório hello-manifests**:
   - Vá em **Commits** - deve haver um commit do "GitHub Action Bot"

4. **🔄 ArgoCD**:
   - A aplicação será atualizada automaticamente (se configurado como Automatic)

### 6.4 Verificação Final

```bash
# Acessar a aplicação atualizada
curl http://localhost:8081
```

Deve retornar: `{"message": "Meu pipeline de CI/CD funcionou!"}`
<img width="529" height="154" alt="print 7" src="https://github.com/user-attachments/assets/0a72efc2-36ed-428b-a88a-63ac3347b0a3" />


## 🛠️ Solução de Problemas Comuns

### ❌ Pipeline Falha no Build

- Verifique se o Dockerfile está correto
- Confirme que os segredos do Docker Hub estão configurados corretamente

### ❌ Erro de Permissão SSH

- Verifique se a deploy key tem permissão de escrita
- Confirme que a chave privada foi copiada completamente (sem quebras de linha)

### ❌ ArgoCD Não Sincroniza

- Verifique a URL do repositório nos manifestos
- Confirme que o path está correto (`.` para raiz)
- Verifique os logs do ArgoCD

### ❌ Aplicação Não Responde

```bash
# Verificar pods
kubectl get pods

# Verificar logs do pod
kubectl logs <nome-do-pod>

# Verificar serviços
kubectl get services
```
<img width="646" height="339" alt="print 23" src="https://github.com/user-attachments/assets/2a512714-fc7b-41f6-b507-10eee7096e60" />

## 📊 Estrutura Final do Projeto

### Repositório hello-app
```
hello-app/
├── .github/
│   └── workflows/
│       └── ci-cd.yml
├── main.py
├── Dockerfile
└── requirements.txt
```

### Repositório hello-manifests
```
hello-manifests/
├── deployment.yaml
└── service.yaml
```

## 🎯 Conclusão

Você implementou com sucesso um pipeline completo de CI/CD usando:

- **✅ GitHub Actions** para integração contínua
- **✅ Docker** para containerização
- **✅ ArgoCD** para GitOps e deployment automatizado
- **✅ Kubernetes** para orquestração de containers

Este pipeline automatiza todo o processo desde o commit de código até o deployment em produção, seguindo as melhores práticas de DevOps e GitOps.

---

## 📞 Suporte

Se encontrar problemas:
1. Verifique todos os pré-requisitos
2. Confirme que todos os segredos estão configurados corretamente
3. Consulte a documentação oficial de cada ferramenta

**🎊 Parabéns! Seu pipeline de CI/CD está funcionando!**
