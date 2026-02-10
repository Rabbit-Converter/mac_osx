import SwiftUI

struct ContentView: View {
    @State private var zawgyi: String = ""
    @State private var unicode: String = ""
    @State private var copyState: CopyState = .none
    @State private var lastEditedField: EditedField = .none
    
    // Constants
    private let copyFeedbackDuration: TimeInterval = 1.5
    
    enum CopyState {
        case none
        case zawgyi
        case unicode
    }
    
    enum EditedField {
        case none
        case zawgyi
        case unicode
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            
            // Converter panels
            HStack(spacing: 16) {
                ConverterPanel(
                    title: "Unicode",
                    text: $unicode,
                    fontName: "Myanmar Sangam MN",
                    isCopying: .constant(copyState == .unicode),
                    onCopy: { copyToClipboard(unicode, state: .unicode) },
                    onTextChange: {
                        if lastEditedField != .unicode {
                            lastEditedField = .unicode
                            zawgyi = Rabbit.uni2zg(unicode)
                        }
                    }
                )
                
                // Divider between panels
                Divider()
                    .padding(.vertical, 20)
                
                ConverterPanel(
                    title: "Zawgyi",
                    text: $zawgyi,
                    fontName: "Zawgyi-One",
                    isCopying: .constant(copyState == .zawgyi),
                    onCopy: { copyToClipboard(zawgyi, state: .zawgyi) },
                    onTextChange: {
                        if lastEditedField != .zawgyi {
                            lastEditedField = .zawgyi
                            unicode = Rabbit.zg2uni(zawgyi)
                        }
                    }
                )
            }
            .padding(20)
            .onChange(of: unicode) { _, _ in
                if lastEditedField == .unicode {
                    lastEditedField = .none
                }
            }
            .onChange(of: zawgyi) { _, _ in
                if lastEditedField == .zawgyi {
                    lastEditedField = .none
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func copyToClipboard(_ text: String, state: CopyState) {
        guard !text.isEmpty else { return }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        // Visual feedback
        copyState = state
        DispatchQueue.main.asyncAfter(deadline: .now() + copyFeedbackDuration) {
            copyState = .none
        }
    }
}

// MARK: - Converter Panel Component
struct ConverterPanel: View {
    let title: String
    @Binding var text: String
    let fontName: String
    @Binding var isCopying: Bool
    let onCopy: () -> Void
    let onTextChange: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with title and copy button
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                Button(action: onCopy) {
                    HStack(spacing: 5) {
                        Image(systemName: isCopying ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                        Text(isCopying ? "Copied" : "Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(isCopying ? .green : .accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isCopying ? Color.green.opacity(0.1) : Color.accentColor.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty)
                .opacity(text.isEmpty ? 0.5 : 1.0)
                .help("Copy \(title) text to clipboard")
            }
            
            // Text editor with native styling
            CustomTextEditor(text: $text, onTextChange: onTextChange)
                .font(name: fontName, size: 15)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        }
    }
}

// MARK: - Custom Text Editor with debouncing for performance
struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onTextChange: (() -> Void)?
    
    var fontName: String?
    var fontSize: CGFloat = 16
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        textView.delegate = context.coordinator
        textView.isRichText = false
        
        // Font
        if let fontName = fontName, let customFont = NSFont(name: fontName, size: fontSize) {
            textView.font = customFont
        } else {
            textView.font = .systemFont(ofSize: fontSize)
        }
        
        // Appearance
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true

        // Ensure document view resizes vertically so scrolling keeps working after edits.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        
        // Disable smart substitutions to prevent interference with Myanmar text encoding
        // Smart quotes and dashes can corrupt Zawgyi/Unicode character sequences
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        
        // Enable editing commands
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        
        // Padding for native feel
        textView.textContainerInset = NSSize(width: 12, height: 12)
        
        // Scroll view styling
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        private var debounceTimer: Timer?
        private let debounceInterval: TimeInterval = 0.3
        
        init(_ parent: CustomTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            
            // Debounce conversion for performance with large text
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                self?.parent.onTextChange?()
            }
        }
    }
}

// MARK: - Font Modifier Extension
extension CustomTextEditor {
    func font(name: String, size: CGFloat = 16) -> CustomTextEditor {
        var editor = self
        editor.fontName = name
        editor.fontSize = size
        return editor
    }
}

#Preview {
    ContentView()
}
