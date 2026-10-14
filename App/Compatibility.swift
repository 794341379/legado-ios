import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum ReadingCompatibility {
    static var usesLegacyUI: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiLegacyCompatibility")
        #else
        false
        #endif
    }
}

struct ReadingNavigationStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            NavigationStack { content }
        } else {
            NavigationView { content }.navigationViewStyle(.stack)
        }
    }
}

struct ReadingLabeledContent<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            LabeledContent(title) { content }
        } else {
            HStack {
                Text(title)
                Spacer()
                content.foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
        }
    }
}

extension ReadingLabeledContent where Content == Text {
    init(_ title: String, value: String) {
        self.init(title) { Text(value) }
    }
}

struct ReadingTextField: View {
    let title: String
    @Binding var text: String
    var axis: Axis

    init(_ title: String, text: Binding<String>, axis: Axis) {
        self.title = title
        _text = text
        self.axis = axis
    }

    var body: some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            TextField(title, text: $text, axis: axis)
        } else if axis == .vertical {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $text).frame(minHeight: 80).accessibilityLabel(title)
            }
        } else {
            TextField(title, text: $text)
        }
    }
}

struct ReadingShareLink<Label: View>: View {
    private let items: [Any]
    private let label: Label

    init(item: String, @ViewBuilder label: () -> Label) {
        items = [item]
        self.label = label()
    }

    init(item: URL, @ViewBuilder label: () -> Label) {
        items = [item]
        self.label = label()
    }

    var body: some View {
        Button { presentShareSheet() } label: { label }
    }

    private func presentShareSheet() {
        guard var presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !(presenter is UIActivityViewController) else { return }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }
}

extension ReadingShareLink where Label == SwiftUI.Label<Text, Image> {
    init(item: URL) {
        self.init(item: item) { SwiftUI.Label("分享", systemImage: "square.and.arrow.up") }
    }
}

struct ReadingPhotoPicker<Label: View>: View {
    let onData: (Data) -> Void
    let onError: (Error) -> Void
    @ViewBuilder var label: Label
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: { label }
            .sheet(isPresented: $isPresented) {
                ReadingPhotoPickerController { result in
                    isPresented = false
                    guard let result else { return }
                    switch result {
                    case .success(let data): onData(data)
                    case .failure(let error): onError(error)
                    }
                }
            }
    }
}

private struct ReadingPhotoPickerController: UIViewControllerRepresentable {
    let onResult: @MainActor (Result<Data, Error>?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onResult: @MainActor (Result<Data, Error>?) -> Void

        init(onResult: @escaping @MainActor (Result<Data, Error>?) -> Void) {
            self.onResult = onResult
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { onResult(nil); return }
            let identifier = provider.registeredTypeIdentifiers.first {
                UTType($0)?.conforms(to: .image) == true
            } ?? UTType.image.identifier
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { [weak self] data, error in
                Task { @MainActor in
                    if let data { self?.onResult(.success(data)) }
                    else { self?.onResult(.failure(error ?? CocoaError(.fileReadCorruptFile))) }
                }
            }
        }
    }
}

enum ReadingSheetDetent { case medium, large }

extension View {
    @ViewBuilder
    func readingNumericTransition() -> some View {
        if #available(iOS 16.0, *) { contentTransition(.numericText()) }
        else { self }
    }

    @ViewBuilder
    func readingNavigationDestination<Destination: View>(
        isPresented: Binding<Bool>, @ViewBuilder destination: () -> Destination
    ) -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            navigationDestination(isPresented: isPresented, destination: destination)
        } else {
            background(NavigationLink(isActive: isPresented, destination: destination) { EmptyView() }.hidden())
        }
    }

    @ViewBuilder
    func readingScrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            scrollContentBackground(.hidden)
        } else {
            background(ReadingUIKitConfiguration { controller in
                func clearTables(in view: UIView) {
                    if let table = view as? UITableView { table.backgroundColor = .clear }
                    for child in view.subviews { clearTables(in: child) }
                }
                if let parent = controller.parent { clearTables(in: parent.view) }
            })
        }
    }

    @ViewBuilder
    func readingScrollDismissesKeyboard() -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            scrollDismissesKeyboard(.immediately)
        } else {
            simultaneousGesture(DragGesture().onChanged { _ in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
        }
    }

    @ViewBuilder
    func readingTabBarBackground() -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            toolbarBackground(ReadingTheme.canvas, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
        } else {
            background(ReadingUIKitConfiguration { controller in
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor(ReadingTheme.canvas)
                controller.tabBarController?.tabBar.standardAppearance = appearance
                controller.tabBarController?.tabBar.scrollEdgeAppearance = appearance
            })
        }
    }

    @ViewBuilder
    func readingTabBarHidden() -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            toolbar(.hidden, for: .tabBar)
        } else {
            background(ReadingHiddenTabBar())
        }
    }

    @ViewBuilder
    func readingHomeIndicatorHidden(_ hidden: Bool) -> some View {
        if #available(iOS 16.0, *) {
            persistentSystemOverlays(hidden ? .hidden : .automatic)
        } else {
            self
        }
    }

    @ViewBuilder
    func readingPresentationDetents(_ detents: [ReadingSheetDetent]) -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            presentationDetents(Set(detents.map { $0 == .medium ? PresentationDetent.medium : .large }))
        } else {
            background(ReadingUIKitConfiguration { controller in
                var current: UIViewController? = controller
                while let candidate = current {
                    if let sheet = candidate.presentationController as? UISheetPresentationController {
                        sheet.detents = detents.map { $0 == .medium ? .medium() : .large() }
                        break
                    }
                    current = candidate.parent
                }
            })
        }
    }

    @ViewBuilder
    func readingPresentationDragIndicator() -> some View {
        if #available(iOS 16.0, *), !ReadingCompatibility.usesLegacyUI {
            presentationDragIndicator(.visible)
        } else {
            background(ReadingUIKitConfiguration { controller in
                var current: UIViewController? = controller
                while let candidate = current {
                    if let sheet = candidate.presentationController as? UISheetPresentationController {
                        if !sheet.prefersGrabberVisible { sheet.prefersGrabberVisible = true }
                        break
                    }
                    current = candidate.parent
                }
            })
        }
    }
}

private struct ReadingUIKitConfiguration: UIViewControllerRepresentable {
    let configure: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(configure: configure) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.configure = configure }

    final class Controller: UIViewController {
        var configure: (UIViewController) -> Void

        init(configure: @escaping (UIViewController) -> Void) {
            self.configure = configure
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); configure(self) }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); configure(self) }
    }
}

private struct ReadingHiddenTabBar: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private weak var hiddenBar: UITabBar?
        private var previouslyHidden = false

        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard let bar = tabBarController?.tabBar else { return }
            hiddenBar = bar
            previouslyHidden = bar.isHidden
            bar.isHidden = true
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            hiddenBar?.isHidden = previouslyHidden
        }
    }
}
