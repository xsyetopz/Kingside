import Foundation
import Testing

@testable import ChessContent

@Suite struct ChatFilterTests {
    private let filter = ChatFilter(note: "Test list.", words: ["ass", "damn", "shit"])

    @Test func masksWholeWordsIgnoringCase() {
        #expect(filter.masked("Damn it") == "•••• it")
        #expect(filter.masked("DAMN SHIT") == "•••• ••••")
        #expect(filter.masked("good game") == "good game")
    }

    @Test func keepsWordsThatContainAListedWord() {
        #expect(filter.masked("class assistant passage") == "class assistant passage")
        #expect(filter.masked("ass") == "•••")
    }

    @Test func punctuationIsABoundary() {
        #expect(filter.masked("damn!") == "••••!")
        #expect(filter.masked("(ass), shit.") == "(•••), ••••.")
        #expect(filter.masked("well-damn") == "well-••••")
        #expect(filter.masked("damn_it") == "••••_it")
        #expect(filter.masked("...") == "...")
        #expect(filter.masked("") == "")
    }

    @Test func digitsBelongToTheWord() {
        #expect(filter.masked("damn2") == "damn2")
    }

    @Test func bundledListIsValid() throws {
        let catalog = try ContentCatalog.load()
        #expect(catalog.chatFilter.problem == nil)
        #expect(catalog.chatFilter.masked("well shit.") == "well ••••.")
        #expect(catalog.attribution(id: "ldnoobw") != nil)
        #expect(catalog.chatFilter.masked("What a class act") == "What a class act")
    }

    @Test func validationRejectsBadLists() {
        #expect(ChatFilter(note: "x", words: []).problem != nil)
        #expect(ChatFilter(note: "", words: ["a"]).problem != nil)
        #expect(ChatFilter(note: "x", words: ["Damn"]).problem != nil)
        #expect(ChatFilter(note: "x", words: ["two words"]).problem != nil)
        #expect(ChatFilter(note: "x", words: ["a", "a"]).problem != nil)
        #expect(ChatFilter(note: "x", words: [""]).problem != nil)
    }

    @Test func reportURLPercentEncodesTheName() throws {
        let lichess = try ContentCatalog.load().services.lichess
        #expect(lichess.reportURL(username: "Some_User-1")?.absoluteString == "\(lichess.baseURL.absoluteString)/report?username=Some_User-1")
        #expect(lichess.reportURL(username: "a b&c=d")?.absoluteString.hasSuffix("/report?username=a%20b%26c%3Dd") == true)
    }
}
