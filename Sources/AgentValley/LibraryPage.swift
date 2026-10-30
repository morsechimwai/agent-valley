import SwiftUI

extension Format {
    static let library = "Library"
    static let openPDF = "Open PDF"
    static let noBooks = "No books yet. When a sub-agent hands work back, it lands here."

    static func libraryHelp(showing: Bool) -> String {
        showing ? "Back to agents" : "Library"
    }

    static func libraryFoot(since: Date, calendar: Calendar) -> String {
        "Kept since \(date("MMM d, yyyy", since, calendar)) · until the project folder is gone"
    }

    static func shelfMeta(books: Int) -> String {
        books == 1 ? "1 book" : "\(books) books"
    }

    /// "2 · today", "3 · Oct 27", "4 · Dec 30, 2025"; "2 new" in its place while chapters wait to be read.
    static func bookMeta(chapters: Int, newCount: Int, last: Date, now: Date, calendar: Calendar) -> String {
        if newCount > 0 { return newDocs(newCount) }
        let day: String
        if calendar.isDate(last, inSameDayAs: now) {
            day = "today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(last, inSameDayAs: yesterday) {
            day = "yesterday"
        } else {
            day = date(calendar.isDate(last, equalTo: now, toGranularity: .year) ? "MMM d" : "MMM d, yyyy", last, calendar)
        }
        return "\(chapters) · \(day)"
    }
}

/// Green, the colour of done, as "N new" on the panel's book.
private let newColor = rgb(0x3CB55E)

/// Books are made here one at a time: a big one takes a second or two, too long for the main thread.
private let bookMaker = DispatchQueue(label: "agent-valley.book-pdf", qos: .userInitiated)

/// The Library page of the panel: the work the sub-agents handed back, one book a session, on a
/// shelf a project. A shelf opens to its books; a book opens as a PDF. It stands where the list
/// was, as History does, on the panel's own scroll.
struct LibraryPage: View {
    let store: AgentStore
    @ObservedObject var state: NotchState
    private let home: String
    private let calendar = HistoryReport.calendar()
    @State private var shelves: [Shelf] = []
    /// The first chapter's title by session, for the books Claude Code never named.
    @State private var titles: [String: String] = [:]
    @State private var since: Date?
    @State private var problem: String?
    /// The sessions whose PDF is being made.
    @State private var making: Set<String> = []

    init(store: AgentStore, state: NotchState, home: String = NSHomeDirectory()) {
        self.store = store
        self.state = state
        self.home = home
    }

    var body: some View {
        let open = shelves.first { $0.key == state.libraryShelf }
        VStack(alignment: .leading, spacing: 10) {
            if let open {
                upToShelves(open.name)
            } else {
                Text(verbatim: Format.library).bold().frame(height: 22).accessibilityAddTraits(.isHeader)
            }
            if let problem { ProblemLine(text: problem) }
            if let open {
                VStack(spacing: 0) {
                    ForEach(open.books, id: \.session) { book in
                        BookLine(book: book, title: title(book), calendar: calendar, making: making.contains(book.session)) {
                            read(book, on: open)
                        }
                    }
                }
            } else if shelves.isEmpty {
                Text(verbatim: Format.noBooks).foregroundStyle(.white.opacity(0.6))
            } else {
                VStack(spacing: 0) {
                    ForEach(shelves, id: \.key) { shelf in
                        ShelfLine(shelf: shelf) { state.libraryShelf = shelf.key }
                    }
                }
            }
            if open == nil, let since {
                Text(verbatim: Format.libraryFoot(since: since, calendar: calendar))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .onAppear(perform: reload)
    }

    /// ‹ Library / the shelf's name: back up to every shelf.
    private func upToShelves(_ name: String) -> some View {
        Button { state.libraryShelf = nil } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                Text(verbatim: Format.library + " /")
                Text(verbatim: name).bold().foregroundStyle(.white).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .contentShape(Rectangle())
            .hoverFill()
            .padding(.leading, -6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Back to library"))
    }

    private func title(_ book: BookSummary) -> String {
        book.title.isEmpty ? titles[book.session] ?? "" : book.title
    }

    /// The shelves as they stand. Projects whose folders have gone are marked so, and dropped
    /// for good once gone long enough. ponytail: read on the main thread as the page appears
    /// (an untitled book reads its chapters whole for a title); move it off the main thread if
    /// a big library makes the page stutter as it opens.
    private func reload() {
        guard let library = store.library else { return }
        let places = library.places()
        let books = library.books()
        let all = Library.shelves(books, home: home, checkouts: places.checkouts, remotes: places.remotes)
        let swept = Library.sweep(all, missing: library.missing(), now: Date(), exists: FileManager.default.fileExists(atPath:))
        for (key, day) in swept.set { library.setMissing(key, since: day) }
        for key in swept.clear { library.setMissing(key, since: nil) }
        let gone = Set(swept.delete)
        let sessions = all.filter { gone.contains($0.key) }.flatMap { $0.books.map(\.session) }
        if !sessions.isEmpty { library.forget(sessions: sessions) }
        for key in swept.delete { library.setMissing(key, since: nil) }
        shelves = swept.shown
        titles = Dictionary(uniqueKeysWithValues: books.filter(\.title.isEmpty).map {
            ($0.session, library.chapters(session: $0.session).first?.title ?? "")
        })
        since = library.oldest() ?? library.since
    }

    /// The book as a PDF in the default app, and what it holds read: its "N new" goes once the
    /// library has the look. Made off the main thread; a click while it is made does nothing.
    private func read(_ book: BookSummary, on shelf: Shelf) {
        guard let library = store.library, !making.contains(book.session) else { return }
        making.insert(book.session)
        let title = title(book), project = shelf.name, calendar = calendar
        bookMaker.async {
            // The look is as of the chapters read: one that comes while the PDF is made stays new.
            let looked = Date()
            let chapters = library.chapters(session: book.session)
            let made = Result { try BookPDF.write(BookDocument(title: title, project: project, chapters: chapters), calendar: calendar) }
            DispatchQueue.main.async {
                making.remove(book.session)
                switch made {
                case .success(let file):
                    NSWorkspace.shared.open(file)
                    problem = nil
                    store.saw(Set(chapters.map(\.agent)), at: looked, then: reload)
                case .failure(let error):
                    problem = Format.couldNotMakePDF(error.localizedDescription)
                }
            }
        }
    }
}

/// A project's shelf: its name, what is new on it and how many books, and › to its books.
private struct ShelfLine: View {
    let shelf: Shelf
    let open: () -> Void

    var body: some View {
        let new = shelf.newCount > 0 ? Format.newDocs(shelf.newCount) : nil
        let books = Format.shelfMeta(books: shelf.books.count)
        Button(action: open) {
            HStack(spacing: 8) {
                BookStack(size: 18).frame(width: 20)
                // verbatim: folder names must never be read as Markdown.
                Text(verbatim: shelf.name).lineLimit(1)
                Spacer(minLength: 8)
                Group {
                    if let new { Text(verbatim: new).foregroundStyle(newColor) }
                    Text(verbatim: books).foregroundStyle(.white.opacity(0.6))
                }
                .font(.system(size: 10, design: .monospaced))
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .hoverFill()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .accessibilityLabel(Text(verbatim: ([shelf.name, new, books] as [String?]).compactMap { $0 }.joined(separator: ", ")))
    }
}

/// One session's book: the green book, its title, who wrote in it and when. Under the pointer the
/// faces give way to "Open PDF", which a click does; while the PDF is made, a spinner stands there.
private struct BookLine: View {
    let book: BookSummary
    let title: String
    let calendar: Calendar
    let making: Bool
    let open: () -> Void
    @State private var over = false

    var body: some View {
        let types = Array(book.types.prefix(3))
        let meta = Format.bookMeta(chapters: book.chapters, newCount: book.newCount, last: book.last, now: Date(), calendar: calendar)
        Button(action: open) {
            HStack(spacing: 8) {
                DoneBook().frame(width: 20)
                // verbatim: titles come from transcripts and must never be read as Markdown.
                Text(verbatim: title).lineLimit(1)
                Spacer(minLength: 8)
                if !over && !making {
                    HStack(spacing: 1) {
                        ForEach(types, id: \.self) { type in
                            let person = MascotKind(type: type).person
                            Pixels(cells: person.rows.map(Array.init), size: 15, colour: person.colour)
                        }
                    }
                }
                Text(verbatim: meta)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(book.newCount > 0 ? AnyShapeStyle(newColor) : AnyShapeStyle(.white.opacity(0.6)))
                if making {
                    ProgressView().controlSize(.small)
                } else if over {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                        Text(verbatim: Format.openPDF)
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .frame(minHeight: 22)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .hoverFill()
            .onHover { over = $0 }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .accessibilityLabel(Text(verbatim: ([title] + types.map { Format.crewName(type: $0) } + [meta]).joined(separator: ", ")))
        .accessibilityHint(Text(verbatim: Format.openPDF))
    }
}
