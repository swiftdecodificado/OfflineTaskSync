import Testing
@testable import Tasks

@Suite struct AppLanguageTests {
    @Test(arguments: ["en", "en_US", "en-GB"])
    func englishLocalesUseEnglishResources(identifier: String) {
        #expect(AppLanguage.resolve(identifier) == .english)
    }

    @Test(arguments: ["pt-BR", "pt_BR", "pt-PT"])
    func portugueseLocalesUsePortugueseResources(identifier: String) {
        #expect(AppLanguage.resolve(identifier) == .portuguese)
    }

    @Test func automaticAndUnsupportedLanguagesUseSystemFallback() {
        #expect(AppLanguage.resolve(nil) == .system)
        #expect(AppLanguage.resolve("system") == .system)
        #expect(AppLanguage.resolve("fr_FR") == .system)
    }
}
