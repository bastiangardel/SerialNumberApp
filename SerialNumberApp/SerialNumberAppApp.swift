import CoreData
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import Cocoa
#endif

#if os(iOS)
import Combine
#endif

#if os(iOS)
let storyboard = UIStoryboard(name: "StoryboardIos", bundle: nil)
#elseif os(macOS)
let storyboard = NSStoryboard(name: "Storyboardmacos", bundle: nil)
#endif

#if os(macOS)
// Ajout d'une extension pour détecter les touches sur la vue
struct KeyEventHandling: NSViewRepresentable {
    var action: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            action(event)
            return event
        }
        context.coordinator.keyDownMonitor = keyDownMonitor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        var keyDownMonitor: Any?
        
        deinit {
            if let monitor = keyDownMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}


extension View {
    func onKeyDown(perform action: @escaping (NSEvent) -> Void) -> some View {
        self.background(KeyEventHandling(action: action))
    }
}

// Modificateur de fenêtre personnalisé
struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func configureWindow(_ callback: @escaping (NSWindow) -> Void) -> some View {
        self.background(WindowAccessor(callback: callback))
    }
}
#endif

#if os(iOS)
class KeyboardObserver: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0

    private var cancellables = Set<AnyCancellable>() // Utiliser un Set<AnyCancellable>

    init() {
        // Observer les notifications de clavier
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { notification in
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height
            }
            .sink { [weak self] height in
                self?.keyboardHeight = height
            }
            .store(in: &cancellables) // Stocker l'abonnement dans le Set

        // Observer quand le clavier est caché
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                self?.keyboardHeight = 0
            }
            .store(in: &cancellables) // Stocker l'abonnement dans le Set
    }
}
#endif

// Vue principale pour la liste des numéros de série
struct SerialNumberListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: SerialNumber.entity(),
        sortDescriptors: []
    ) private var serialNumbers: FetchedResults<SerialNumber>

    @State private var newSerialNumber: String = ""
    @State private var selectedSerialNumbers: Set<SerialNumber> = []
    @State private var errorMessage: String? = nil
    @FocusState private var isTextFieldFocused: Bool
    @FocusState private var isListFocused: Bool
    
#if os(iOS)
    @StateObject private var keyboardObserver = KeyboardObserver()
#endif
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                
                Text("Liste des numéros de série")
                    .font(.title)
                    .frame(maxWidth: .infinity, alignment: .center)  // Centré horizontalement
                
                HStack {
                    TextField("Entrer un numéro de série", text: $newSerialNumber)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            addSerialNumber()
                        }
                        .padding(.leading, 10)  // Marge à gauche de 10 px
                        .padding(.trailing, 5)  // Un peu moins de marge à droite pour le champ de saisie
                    
                    Button(action: addSerialNumber) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                    }
                    .padding(.trailing, 10)  // Marge à droite pour le bouton
                }
                .padding(.horizontal, 10)  // Appliquer la marge horizontale à tout le HStack
                
                // Message d'erreur
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                
#if os(macOS)
                if let exportSuccessMessage = exportSuccessMessage {
                    Text(exportSuccessMessage)
                        .foregroundColor(.green)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.opacity) // Ajoute une transition d'opacité
                        .animation(.easeInOut(duration: 0.5), value: exportSuccessMessage) // Animation
                }
#endif
                Spacer()
                
#if os(iOS)
                EditButton()
#endif
                
                // Liste des numéros de série avec prise en charge de la sélection
                List(selection: $selectedSerialNumbers) {
                    ForEach(serialNumbers) { serialNumber in
                        Text(serialNumber.value ?? "")
                            .tag(serialNumber)  // Tag chaque élément pour la sélection
                    }
                    .onDelete(perform: deleteSerialNumber)
                    
                }
                .padding(.horizontal, 10)  // Appliquer la marge horizontale à la liste
                .focusable()
                .focused($isListFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(macOS)
                .onKeyDown { event in
                    // Si l'utilisateur appuie sur Backspace et qu'il y a des numéros sélectionnés
                    if event.keyCode == 51 { // 51 est le code pour la touche Backspace
                        deleteSelectedSerialNumbers()
                        
                    }
                }
#endif
                
                Spacer()
                // Boutons d'action
                HStack {
                    Button(action: deleteSelectedSerialNumbers) {
                        Label("Supprimer", systemImage: "trash.fill")
                            .foregroundColor(.red)
                    }
                    .padding()
                    .disabled(selectedSerialNumbers.isEmpty)
                    
                    Button(action: deleteAllSerialNumbers) {
                        Label("Vider", systemImage: "trash.fill")
                            .foregroundColor(.red)
                    }
                    .padding()
                    
                    Button("Exporter") {
#if os(macOS)
                        saveToCSV()
#else
                        shareCSV()
#endif
                    }
                    .padding()
                    .disabled(serialNumbers.isEmpty)  // Désactive si la liste est vide
                    
#if os(macOS)
                    Button("Quitter") {
                        NSApp.terminate(nil)
                    }
                    .padding()
                    .foregroundColor(.blue)
#endif
                }
                .padding(.horizontal, 10)  // Appliquer la marge horizontale à l'HStack des boutons
                
                Spacer()
                
            }
#if os(macOS)
            .padding(.horizontal, 10)  // Applique la marge à l'ensemble du VStack
#else
            .frame(width: geometry.size.width, height: geometry.size.height - keyboardObserver.keyboardHeight) // Ajuste la hauteur en fonction de la hauteur du clavier
            .padding(.bottom, keyboardObserver.keyboardHeight) // Compense la hauteur du clavier
            .animation(.easeInOut, value: keyboardObserver.keyboardHeight)
            .onTapGesture {
                hideKeyboard()
            }
#endif
        }
        //.edgesIgnoringSafeArea(.all)
    }
    
#if os(iOS)
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
#endif
    
    // Fonction pour ajouter un numéro de série
    func addSerialNumber() {
        guard !newSerialNumber.isEmpty else { return }

        // Vérifie les doublons
        if serialNumbers.contains(where: { $0.value == newSerialNumber }) {
            errorMessage = "Ce numéro de série existe déjà."
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                errorMessage = nil
            }
            return
        }

        let newSerial = SerialNumber(context: viewContext)
        newSerial.value = newSerialNumber

        do {
            try viewContext.save()
            newSerialNumber = ""  // Efface le champ de texte après la sauvegarde
            errorMessage = nil
        } catch {
            errorMessage =
                "Erreur lors de la sauvegarde du numéro de série : \(error.localizedDescription)"
        }
    }

    // Fonction pour supprimer un numéro de série
    func deleteSerialNumber(at offsets: IndexSet) {
        offsets.map { serialNumbers[$0] }.forEach(viewContext.delete)

        do {
            try viewContext.save()
        } catch {
            errorMessage =
                "Erreur lors de la suppression du numéro de série : \(error.localizedDescription)"
        }
    }

    // Fonction pour supprimer tous les numéros de série
    func deleteAllSerialNumbers() {
        for serialNumber in serialNumbers {
            viewContext.delete(serialNumber)
        }

        do {
            try viewContext.save()
        } catch {
            errorMessage =
                "Erreur lors de la suppression de tous les numéros de série : \(error.localizedDescription)"
        }
    }

    // Fonction pour supprimer les numéros de série sélectionnés
    func deleteSelectedSerialNumbers() {
        for serialNumber in selectedSerialNumbers {
            viewContext.delete(serialNumber)
        }

        do {
            try viewContext.save()
            selectedSerialNumbers.removeAll()  // Efface la sélection après suppression
        } catch {
            errorMessage =
                "Erreur lors de la suppression des numéros de série sélectionnés : \(error.localizedDescription)"
        }
    }

    // Fonction pour sauvegarder les numéros de série dans un fichier CSV (macOS)
    #if os(macOS)
    // Message de confirmation pour l'exportation réussi
    @State private var exportSuccessMessage: String?

    // Fonction d'exportation mise à jour avec confirmation
    func saveToCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "serial_numbers.csv"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                let header = "Serial Number\n"
                let content = header + serialNumbers.map { $0.value ?? "" }.joined(separator: "\n")

                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    exportSuccessMessage = "Fichier exporté avec succès à \(url)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        exportSuccessMessage = nil
                    }
                } catch {
                    errorMessage = "Erreur lors de la sauvegarde du fichier CSV : \(error.localizedDescription)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        errorMessage = nil
                    }
                }
            }
        }
    }
    #endif

    // Alternative iOS pour partager le contenu CSV
    #if os(iOS)
        func shareCSV() {
            let header = "Serial Number\n"
            let content =
                header
                + serialNumbers.map { $0.value ?? "" }.joined(separator: "\n")
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("serial_numbers.csv")

            do {
                try content.write(
                    to: tempURL, atomically: true, encoding: .utf8)
                let activityVC = UIActivityViewController(
                    activityItems: [tempURL], applicationActivities: nil)

                if let topController = UIApplication.shared.windows.first?
                    .rootViewController
                {
                    topController.present(
                        activityVC, animated: true, completion: nil)
                }
            } catch {
                errorMessage =
                    "Erreur lors de la préparation du fichier CSV pour le partage : \(error.localizedDescription)"
            }
        }
    #endif
    
    
    #if os(macOS)
    func applicationShouldTerminateAfterLastWindowClosed (_ theApplication: NSApplication) -> Bool {
        return true
    }
    #endif

}

#Preview {
    SerialNumberListView()
}

// Core Data Persistence Controller
struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SerialNumberApp")  // Nom du modèle Core Data
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(
                fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                print("Core Data error: \(error), \(error.userInfo)")
                fatalError(
                    "Failed to load Core Data stack: \(error), \(error.userInfo)"
                )
            }
        }
    }
}

@main
struct SerialNumberApp: App {
    let persistenceController = PersistenceController.shared
    
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    
    var body: some Scene {
        WindowGroup {
            SerialNumberListView()
                .environment(
                    \.managedObjectContext,
                    persistenceController.container.viewContext)
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 300)
                #else
                //.ignoresSafeArea()
                #endif
        }
        #if os(macOS)
            .windowStyle(.hiddenTitleBar)  // Utilisation uniquement pour macOS
            .defaultSize(width: 500, height: 300)
        #endif
    }
    
}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif
