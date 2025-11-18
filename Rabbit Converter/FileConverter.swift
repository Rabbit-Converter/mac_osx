//
//  FileConverter.swift
//  Rabbit Converter
//
//  Created by Kiro on 11/17/25.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

class FileConverter {
    
    // MARK: - Configuration
    
    private static let textFileExtensions = ["txt", "html", "htm", "xml", "json", "csv", "md", "swift", "js", "css", "py", "java"]
    
    static func selectFolderAndConvert() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to convert documents"
        
        panel.begin { response in
            if response == .OK, let sourceURL = panel.url {
                self.convertFolder(sourceURL: sourceURL)
            }
        }
    }
    
    private static func convertFolder(sourceURL: URL) {
        // Ask for target folder
        let savePanel = NSOpenPanel()
        savePanel.canChooseFiles = false
        savePanel.canChooseDirectories = true
        savePanel.allowsMultipleSelection = false
        savePanel.message = "Select destination folder for converted files"
        savePanel.prompt = "Select"
        
        savePanel.begin { response in
            if response == .OK, let targetURL = savePanel.url {
                // Start accessing security-scoped resources (for sandboxed apps)
                // Note: This may return false for regular file system access, which is fine
                let sourceAccess = sourceURL.startAccessingSecurityScopedResource()
                let targetAccess = targetURL.startAccessingSecurityScopedResource()
                
                let group = DispatchGroup()
                group.enter()
                
                DispatchQueue.global(qos: .userInitiated).async {
                    self.processFolder(source: sourceURL, target: targetURL)
                    group.leave()
                }
                
                // Cleanup after processing completes
                group.notify(queue: .main) {
                    if sourceAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                    if targetAccess {
                        targetURL.stopAccessingSecurityScopedResource()
                    }
                }
            }
        }
    }
    
    private static func processFolder(source: URL, target: URL) {
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else {
            let errorMsg = "Failed to read source folder: \(source.path)"
            print(errorMsg)
            showError(errorMsg)
            return
        }
        
        var convertedCount = 0
        var errorCount = 0
        var errorMessages: [String] = []
        
        for case let fileURL as URL in enumerator {
            // Get relative path components
            let sourceComponents = source.pathComponents
            let fileComponents = fileURL.pathComponents
            
            guard fileComponents.count > sourceComponents.count else { continue }
            
            let relativeComponents = Array(fileComponents.dropFirst(sourceComponents.count))
            guard !relativeComponents.isEmpty else { continue }
            
            // Build target URL
            var targetFileURL = target
            for component in relativeComponents {
                targetFileURL.appendPathComponent(component)
            }
            
            do {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        // Create directory
                        try fileManager.createDirectory(at: targetFileURL, withIntermediateDirectories: true)
                    } else {
                        // Ensure parent directory exists
                        let parentDir = targetFileURL.deletingLastPathComponent()
                        if !fileManager.fileExists(atPath: parentDir.path) {
                            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
                        }
                        // Process file
                        let ext = fileURL.pathExtension.lowercased()
                        
                        switch ext {
                        case "docx":
                            try convertDocx(source: fileURL, target: targetFileURL)
                            convertedCount += 1
                        case "xlsx":
                            try convertXlsx(source: fileURL, target: targetFileURL)
                            convertedCount += 1
                        case "pptx":
                            try convertPptx(source: fileURL, target: targetFileURL)
                            convertedCount += 1
                        default:
                            // Check if it's a text file
                            if isTextFile(fileURL) {
                                try convertTextFile(source: fileURL, target: targetFileURL)
                                convertedCount += 1
                            } else {
                                // Copy binary files as-is
                                try fileManager.copyItem(at: fileURL, to: targetFileURL)
                            }
                        }
                    }
                }
            } catch {
                let errorMsg = "\(fileURL.lastPathComponent): \(error.localizedDescription)"
                print("Error processing \(errorMsg)")
                errorMessages.append(errorMsg)
                errorCount += 1
            }
        }
        
        DispatchQueue.main.async {
            showSuccess(convertedCount: convertedCount, errorCount: errorCount, errorMessages: errorMessages, targetURL: target)
        }
    }
    
    // MARK: - Document Converters
    
    private static func convertDocx(source: URL, target: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            do {
                try FileManager.default.removeItem(at: tempDir)
            } catch {
                print("Warning: Failed to cleanup temp directory \(tempDir.path): \(error)")
            }
        }
        
        // Unzip
        try unzip(source: source, destination: tempDir)
        
        // Convert document.xml with regex for robust font replacement
        let docXMLPath = tempDir.appendingPathComponent("word/document.xml")
        if FileManager.default.fileExists(atPath: docXMLPath.path) {
            var content = try String(contentsOf: docXMLPath, encoding: .utf8)
            // Use regex to match font attributes more reliably
            content = content.replacingOccurrences(
                of: "=\"Zawgyi-One\"",
                with: "=\"Myanmar Text\"",
                options: .regularExpression
            )
            content = Rabbit.zg2uni(content)
            try content.write(to: docXMLPath, atomically: true, encoding: .utf8)
        }
        
        // Zip back
        try zip(source: tempDir, destination: target)
    }
    
    private static func convertXlsx(source: URL, target: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            do {
                try FileManager.default.removeItem(at: tempDir)
            } catch {
                print("Warning: Failed to cleanup temp directory \(tempDir.path): \(error)")
            }
        }
        
        // Unzip
        try unzip(source: source, destination: tempDir)
        
        // Convert sharedStrings.xml
        let sharedStringsPath = tempDir.appendingPathComponent("xl/sharedStrings.xml")
        if FileManager.default.fileExists(atPath: sharedStringsPath.path) {
            let content = try String(contentsOf: sharedStringsPath, encoding: .utf8)
            let converted = Rabbit.zg2uni(content)
            try converted.write(to: sharedStringsPath, atomically: true, encoding: .utf8)
        }
        
        // Convert styles.xml with regex for robust font replacement
        let stylesPath = tempDir.appendingPathComponent("xl/styles.xml")
        if FileManager.default.fileExists(atPath: stylesPath.path) {
            var content = try String(contentsOf: stylesPath, encoding: .utf8)
            content = content.replacingOccurrences(
                of: "val=\"Zawgyi-One\"",
                with: "val=\"Myanmar Text\"",
                options: .regularExpression
            )
            try content.write(to: stylesPath, atomically: true, encoding: .utf8)
        }
        
        // Zip back
        try zip(source: tempDir, destination: target)
    }
    
    private static func convertPptx(source: URL, target: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            do {
                try FileManager.default.removeItem(at: tempDir)
            } catch {
                print("Warning: Failed to cleanup temp directory \(tempDir.path): \(error)")
            }
        }
        
        // Unzip
        try unzip(source: source, destination: tempDir)
        
        // Convert all slide XML files with regex for robust font replacement
        let slidesDir = tempDir.appendingPathComponent("ppt/slides")
        if let files = try? FileManager.default.contentsOfDirectory(at: slidesDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "xml" {
                var content = try String(contentsOf: file, encoding: .utf8)
                content = Rabbit.zg2uni(content)
                // Use regex to handle variations in XML formatting (spaces, quotes)
                content = content.replacingOccurrences(
                    of: "typeface\\s*=\\s*[\"']Zawgyi-One[\"']",
                    with: "typeface=\"Myanmar Text\"",
                    options: .regularExpression
                )
                try content.write(to: file, atomically: true, encoding: .utf8)
            }
        }
        
        // Zip back
        try zip(source: tempDir, destination: target)
    }
    
    private static func convertTextFile(source: URL, target: URL) throws {
        let zawgyi = try String(contentsOf: source, encoding: .utf8)
        let unicode = Rabbit.zg2uni(zawgyi)
        try unicode.write(to: target, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Zip Utilities
    
    private static func unzip(source: URL, destination: URL) throws {
        let task = Process()
        let errorPipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-q", source.path, "-d", destination.path]
        task.standardError = errorPipe
        
        try task.run()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("Unzip error: \(errorOutput)")
            throw NSError(
                domain: "FileConverter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to unzip file: \(errorOutput)"]
            )
        }
    }
    
    private static func zip(source: URL, destination: URL) throws {
        // Create zip in temp location first
        let tempZip = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        
        defer {
            try? FileManager.default.removeItem(at: tempZip)
        }
        
        let task = Process()
        let errorPipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        task.currentDirectoryURL = source
        task.arguments = ["-r", "-q", tempZip.path, "."]
        task.standardError = errorPipe
        
        try task.run()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("Zip error: \(errorOutput)")
            throw NSError(
                domain: "FileConverter",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to zip file: \(errorOutput)"]
            )
        }
        
        // Read data and write to destination (works better with sandboxing)
        let data = try Data(contentsOf: tempZip)
        try data.write(to: destination)
    }
    
    // MARK: - Helpers
    
    private static func isTextFile(_ url: URL) -> Bool {
        // First check extension for quick lookup
        if textFileExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }
        
        // Fallback to UTType for more accurate detection (macOS 11+)
        if #available(macOS 11.0, *) {
            if let type = UTType(filenameExtension: url.pathExtension) {
                return type.conforms(to: .text) || type.conforms(to: .sourceCode)
            }
        }
        
        return false
    }
    
    private static func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Conversion Error"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.runModal()
        }
    }
    
    private static func showSuccess(convertedCount: Int, errorCount: Int, errorMessages: [String], targetURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Conversion Complete"
        
        var infoText = "Successfully converted \(convertedCount) file(s)."
        if errorCount > 0 {
            infoText += "\n\n\(errorCount) error(s) occurred:"
            // Show first 5 errors to avoid overwhelming the user
            let displayErrors = errorMessages.prefix(5)
            for error in displayErrors {
                infoText += "\n• \(error)"
            }
            if errorMessages.count > 5 {
                infoText += "\n• ... and \(errorMessages.count - 5) more"
            }
        }
        
        alert.informativeText = infoText
        alert.alertStyle = errorCount > 0 ? .warning : .informational
        alert.addButton(withTitle: "Open Folder")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(targetURL)
        }
    }
}
