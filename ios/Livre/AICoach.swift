import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Coach com a IA da Apple (Apple Intelligence), rodando 100% no iPhone.
/// Nada da conversa sai do aparelho.
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@MainActor
final class AICoach {
    static let baseInstructions = """
    Você é o Coach do Livre, um treinador de bem-estar gentil e prático. Você ajuda a pessoa a mudar hábitos que ela quer deixar \
    e a crescer em todas as áreas da vida: saúde, família, relacionamentos, trabalho, finanças, propósito e fé.
    Como responder:
    - Sempre em português do Brasil, com carinho, de forma direta e curta: no máximo 6 frases ou uma lista curta. Trate a pessoa por "você".
    - Personalize com os dados da pessoa abaixo: lembre os sonhos, as pessoas queridas e os motivos dela quando ajudar.
    - Quando a vontade de voltar ao hábito aparecer, sugira técnicas de bem-estar: observar a vontade passar como uma onda, \
    esperar 15 minutos, checar se está com fome, irritado, sozinho ou cansado, imaginar como vai se sentir amanhã, trocar a rotina, \
    respirar fundo e mudar de ambiente. Termine com um próximo passo concreto.
    - Ao olhar os registros, aponte padrões de horário, emoção e situação, e sugira um plano simples para cada um. \
    Use somente o que está nos dados abaixo e nunca invente horários, dias ou números. Se houver poucos registros, diga isso \
    com carinho, peça para a pessoa registrar os próximos momentos de vontade no app e dê dicas gerais.
    - Seja sempre acolhedor. Um tropeço faz parte do caminho e é uma chance de aprender.
    - Você é um apoio, não um profissional de saúde. Para sintomas físicos, oriente procurar um médico ou o CAPS AD do SUS. \
    Se a pessoa estiver passando por um momento muito difícil, incentive ligar para o CVV no 188, que atende 24 horas.
    """

    private var context = ""
    private var session: LanguageModelSession?
    private var task: Task<Void, Never>?

    func status() -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "deviceNotEligible"
            case .appleIntelligenceNotEnabled: return "appleIntelligenceNotEnabled"
            case .modelNotReady: return "modelNotReady"
            @unknown default: return "unavailable"
            }
        @unknown default:
            return "unavailable"
        }
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: Self.baseInstructions + "\n\nDados da pessoa:\n" + context)
    }

    func start(context: String) {
        self.context = context
        task?.cancel()
        let s = makeSession()
        session = s
        s.prewarm()
    }

    func reset() {
        task?.cancel()
        session = makeSession()
    }

    func send(prompt: String, onText: @escaping (String) -> Void, done: @escaping (String?) -> Void) {
        task?.cancel()
        let s = session ?? makeSession()
        session = s
        task = Task { @MainActor in
            do {
                try await self.run(s, prompt, onText)
                done(nil)
            } catch let e as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = e {
                    // Conversa ficou longa demais: recomeça a sessão mantendo os dados da pessoa.
                    let fresh = self.makeSession()
                    self.session = fresh
                    do { try await self.run(fresh, prompt, onText); done(nil) }
                    catch { done(Self.message(for: error)) }
                } else {
                    done(Self.message(for: e))
                }
            } catch {
                done(Task.isCancelled ? nil : Self.message(for: error))
            }
        }
    }

    private func run(_ s: LanguageModelSession, _ prompt: String, _ onText: @escaping (String) -> Void) async throws {
        var last = Date.distantPast
        var latest = ""
        for try await snap in s.streamResponse(to: prompt) {
            latest = snap.content
            if Date().timeIntervalSince(last) > 0.08 { onText(latest); last = Date() }
        }
        onText(latest)
    }

    private static func message(for error: Error) -> String {
        NSLog("[LivreAI] erro: %@", String(describing: error))
        let guardrail = "Não consegui responder a essa mensagem. Tente dizer de outro jeito. Se você estiver passando por um momento muito difícil, ligue 188 (CVV), 24 horas."
        let language = "A IA do seu iPhone ainda não está disponível no idioma configurado. Confira o idioma da Apple Intelligence em Ajustes."
        if #available(iOS 27.0, *), let e = error as? LanguageModelError {
            switch e {
            case .guardrailViolation: return guardrail
            case .unsupportedLanguageOrLocale: return language
            default: break
            }
        }
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .guardrailViolation: return guardrail
            case .unsupportedLanguageOrLocale: return language
            default: break
            }
        }
        return "Não consegui responder agora. Tente de novo em instantes."
    }
}
#endif
