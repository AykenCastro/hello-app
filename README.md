Tutorial: CI/CD com GitHub Actions e ArgoCDEste guia irá ajudá-lo a criar um pipeline completo onde:CI (Integração Contínua): Você envia um código Python (push) para um repositório. O GitHub Actions automaticamente testa, constrói uma imagem Docker e a envia para o Docker Hub.CD (Entrega Contínua): O mesmo GitHub Action, em seguida, atualiza um segundo repositório (de manifestos) com a nova tag da imagem. O ArgoCD detecta essa mudança e atualiza automaticamente a aplicação no seu Rancher Desktop.Visão Geral da Estratégia: Dois RepositóriosEste projeto exige dois repositórios Git públicos:hello-app (Repositório da Aplicação): Contém o código Python (main.py) e o Dockerfile.hello-manifests (Repositório de Manifestos): Contém os arquivos YAML do Kubernetes (deployment.yaml, service.yaml) que o ArgoCD irá monitorar.Etapa 1: Criar o Repositório 1 (hello-app)Este repositório conterá seu código-fonte.1. Crie e CloneNo GitHub, crie um novo repositório público chamado hello-app. Clone-o para o seu computador:git clone [https://github.com/](https://github.com/)<SEU-USUARIO>/hello-app.git
cd hello-app
2. Crie o main.pyCrie este arquivo com o código FastAPI:# main.py
from fastapi import FastAPI
app = FastAPI()

@app.get("/")
async def root():
    return {"message": "Hello World"}
3. Crie o DockerfileCrie um arquivo chamado Dockerfile (sem extensão) com este conteúdo:# Dockerfile

# 1. Base Image
FROM python:3.9-slim

# 2. Set working directory
WORKDIR /app

# 3. Install dependencies
# (Nota: O 'requirements.txt' é copiado primeiro para aproveitar o cache do Docker)
COPY requirements.txt .
RUN pip install fastapi uvicorn

# 4. Copy app code
COPY . .

# 5. Expose port and run
EXPOSE 80
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "80"]
4. Crie o requirements.txtCrie um arquivo requirements.txt (pode estar vazio por enquanto, apenas para o COPY no Dockerfile funcionar). O RUN já instala o fastapi e uvicorn.touch requirements.txt
5. Envie para o GitHubgit add .
git commit -m "Versão inicial da hello-app"
git push origin main
Etapa 2: Criar o Repositório 2 (hello-manifests)Este repositório conterá seus manifestos do Kubernetes. O ArgoCD irá monitorá-lo.1. Crie e CloneNo GitHub, crie um novo repositório público chamado hello-manifests. Clone-o para outro local no seu computador.# Em uma pasta DIFERENTE da 'hello-app'
git clone [https://github.com/](https://github.com/)<SEU-USUARIO>/hello-manifests.git
cd hello-manifests
2. Crie o deployment.yamlCrie este arquivo. Ele define como rodar sua aplicação.Importante: Substitua <SEU-DOCKERHUB-USERNAME> pelo seu nome de usuário do Docker Hub.# deployment.yaml
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
        # ATENÇÃO: Coloque seu usuário do Docker Hub aqui!
        # O 'initial' será substituído pela GitHub Action
        image: <SEU-DOCKERHUB-USERNAME>/hello-app:initial
        ports:
        - containerPort: 80
3. Crie o service.yamlCrie este arquivo. Ele expõe seu Deployment dentro do cluster.# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-app-service
spec:
  type: ClusterIP
  selector:
    app: hello-app # Deve bater com o label do Deployment
  ports:
  - port: 8080 # Porta que o Service expõe
    targetPort: 80 # Porta que o contêiner escuta (do Dockerfile)
4. Envie para o GitHubgit add .
git commit -m "Manifestos iniciais da hello-app"
git push origin main
Etapa 3: Configurar os Segredos (GitHub Secrets)O seu GitHub Action (no repositório hello-app) precisará de permissões para:Fazer login no Docker Hub.Fazer um "push" (commit) no repositório hello-manifests.Vá para hello-app -> Settings -> Secrets and variables -> Actions e crie:1. Segredos do Docker HubDOCKER_USERNAME: Seu nome de usuário do Docker Hub.DOCKER_PASSWORD: Não é sua senha. Vá ao Docker Hub -> Account Settings -> Security -> New Access Token. Crie um token e cole o valor aqui.2. Segredo de Deploy (SSH Key)Este é o passo mais complexo, pois permite que um repositório (app) escreva em outro (manifestos).a. Gere um par de chaves:No seu terminal local, rode:# -f deploy_key: Salva o par como 'deploy_key' e 'deploy_key.pub'
# -N "": Deixa a senha da chave em branco
ssh-keygen -t rsa -b 4096 -C "github-action-deploy" -f deploy_key -N ""
b. Adicione a Chave Pública (Deploy Key) aos hello-manifests:Vá para o repositório hello-manifests -> Settings -> Deploy keys -> Add deploy key.Title: GitHub ActionKey: Copie e cole o conteúdo do arquivo deploy_key.pub (a chave pública).MARQUE A CAIXA: Allow write access.c. Adicione a Chave Privada (Secret) ao hello-app:Vá para o repositório hello-app -> Settings -> Secrets and variables -> Actions.Crie um novo segredo:Name: SSH_PRIVATE_KEYValue: Copie e cole o conteúdo do arquivo deploy_key (a chave privada).Etapa 4: Criar o GitHub Action (O Pipeline de CI/CD)No seu repositório hello-app, crie a pasta .github/workflows e, dentro dela, o arquivo ci-cd.yml.# .github/workflows/ci-cd.yml
name: CI/CD Pipeline

on:
  push:
    branches: [ main ] # Dispara a action em todo push para a 'main'

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
          # A tag da imagem será o usuário + o hash do commit (ex: usuario/hello-app:a1b2c3d)
          tags: ${{ secrets.DOCKER_USERNAME }}/hello-app:${{ github.sha }}

  # --- JOB 2: UPDATE MANIFESTS (CD/GitOps) ---
  update-manifests:
    runs-on: ubuntu-latest
    needs: build-and-push-docker # Só roda se o Job 1 for um sucesso

    steps:
      - name: Configurar SSH para Git
        uses: webfactory/ssh-agent@v0.5.3
        with:
          ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}

      - name: Checkout repositório de manifestos
        uses: actions/checkout@v3
        with:
          # ATENÇÃO: Substitua <SEU-USUARIO> aqui!
          repository: <SEU-USUARIO>/hello-manifests
          ssh-key: ${{ secrets.SSH_PRIVATE_KEY }} # Usa a chave para autenticar
          path: manifests # Baixa para uma pasta 'manifests'

      - name: Atualizar a tag da imagem no deployment.yaml
        run: |
          # Encontra a linha 'image:' e substitui a tag pela nova (hash do commit)
          sed -i 's|image:.*|image: ${{ secrets.DOCKER_USERNAME }}/hello-app:${{ github.sha }}|' manifests/deployment.yaml
      
      - name: Fazer commit e push da mudança
        run: |
          cd manifests
          git config --global user.name "GitHub Action Bot"
          git config --global user.email "bot@github.com"
          git commit -am "Atualiza tag da imagem para ${{ github.sha }}"
          git push
Importante: Substitua <SEU-USUARIO> no arquivo YAML acima. Após criar este arquivo, envie-o para o hello-app:# No diretório 'hello-app'
git add .github/workflows/ci-cd.yml
git commit -m "Adiciona pipeline de CI/CD"
git push origin main
Este push irá disparar o primeiro pipeline! Você pode assistir em hello-app -> Actions.Etapa 5: Criar o App no ArgoCDEsta etapa conecta seu cluster ao repositório de manifestos.Acesse seu ArgoCD.Clique em "+ NEW APP".Preencha:Application Name: hello-appProject Name: defaultSync Policy: Automatic (ou Manual, se preferir)Repository URL: https://github.com/<SEU-USUARIO>/hello-manifests.git (Aponte para o repositório de manifestos!)Path: . (o diretório raiz)Cluster URL: https://kubernetes.default.svcNamespace: defaultClique em "CREATE" e depois em "SYNC".O ArgoCD irá ler seu hello-manifests, encontrar o deployment.yaml (que já foi atualizado pela Action) e implantar a aplicação no seu Rancher Desktop.Etapa 6: Acessar e Testar o Loop CompletoTeste 1: Acessar a AplicaçãoNo seu terminal, faça o port-forward para o novo serviço que criamos (o service.yaml usa a porta 8080):kubectl port-forward service/hello-app-service 8080:8080
Acesse http://localhost:8080 no seu navegador ou use curl.Você deve ver a mensagem original: {"message": "Hello World"}.Teste 2: O Loop de CI/CDAgora, vamos testar se a automação funciona.No seu computador, vá para a pasta hello-app.Abra o main.py e altere a mensagem:# main.py
...
async def root():
    return {"message": "Meu pipeline de CI/CD funcionou!"}
Faça o commit e push:git add main.py
git commit -m "Testando o pipeline"
git push origin main
Observe a Mágica:GitHub Actions: Vá para hello-app -> Actions. Você verá um novo pipeline "Testando o pipeline" em execução. Espere ele terminar (o Job 1 e o Job 2).Docker Hub: Verifique seu repositório de imagens. Uma nova tag com o hash do último commit terá aparecido.Git (Manifests): Vá para hello-manifests -> Commits. Você verá um novo commit do "GitHub Action Bot" atualizando a tag da imagem no deployment.yaml.ArgoCD: Vá para o ArgoCD. O app hello-app ficará OutOfSync (ou se atualizará sozinho se você escolheu Automatic). Sincronize-o, se necessário.Verificação Final: Atualize http://localhost:8080 no seu navegador. A mensagem deve mudar para: {"message": "Meu pipeline de CI/CD funcionou!"}.Parabéns! Você acabou de completar um ciclo de desenvolvimento, build e deploy totalmente automatizado.
