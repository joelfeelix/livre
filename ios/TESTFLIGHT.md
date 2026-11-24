# Como subir o Livre para o TestFlight

O app iOS carrega o app web (`index.html`) de dentro do próprio aplicativo, então funciona sem internet.
Os dados ficam salvos no aparelho, com uma cópia de segurança em Documentos/livre.json.

## Precisa ter
- Um Mac com Xcode
- Uma conta paga do Apple Developer Program (US$ 99 por ano)

## Passo a passo
1. Clone o repositório e abra `ios/Livre.xcodeproj` no Xcode.
2. Clique no projeto **Livre** → target **Livre** → aba **Signing & Capabilities**:
   - Em **Team**, escolha a sua conta de desenvolvedor.
   - Se o Xcode reclamar do **Bundle Identifier** (`com.livreapp.livre`), troque por um seu, por exemplo `com.seunome.livre`.
3. No App Store Connect (https://appstoreconnect.apple.com) → **Apps** → **+** → **Novo app**:
   - Plataforma iOS, nome "Livre" (ou outro, se já existir), idioma Português (Brasil),
     e o mesmo Bundle ID do passo 2.
4. No Xcode, escolha o destino **Any iOS Device (arm64)** e vá em **Product → Archive**.
5. Quando abrir o Organizer: **Distribute App → App Store Connect → Upload**.
6. Depois de uns 10 a 30 minutos o build aparece em **TestFlight** no App Store Connect.
   - **Teste interno** (pessoas da sua equipe no App Store Connect): libera na hora.
   - **Teste externo** (qualquer e-mail): precisa de uma revisão rápida da Apple, geralmente em 1 dia.

## Atualizar o app
Edite o `index.html` na raiz do repositório. Na hora de compilar, o Xcode copia ele automaticamente
(`ios/sync-web.sh`). Antes de cada novo envio, aumente o **Build** (Signing → General → Identity).

## Se mudar o project.yml
O projeto é gerado com XcodeGen: `brew install xcodegen` e depois `cd ios && xcodegen generate`.
