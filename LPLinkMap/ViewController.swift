//
//  ViewController.swift
//  LPLinkMap
//
//  Created by pengli on 2019/5/24.
//  Copyright © 2019 pengli. All rights reserved.
//

import Cocoa

class ViewController: NSViewController {
    @IBOutlet weak var filePathTextField: NSTextField!
    @IBOutlet weak var keywordsSearchField: NSTextField!
    @IBOutlet weak var indicator: NSProgressIndicator!
    @IBOutlet weak var groupButton: NSButton!
    @IBOutlet var resultTextView: NSTextView!

    var linkMapFileURL: URL?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        resultTextView.string = """
        使用方式:
        1.在XCode中开启编译选项`Write Link Map File`
            XCode -> Project -> Build Settings -> 把Write Link Map File选项设为yes，并指定好linkMap的存储位置
        2.工程编译完成后，在编译目录里找到Link Map文件（txt类型）
            默认的文件地址：~/Library/Developer/Xcode/DerivedData/XXX-xxxxxxxxxxxxx/Build/Intermediates/XXX.build/Debug-iphoneos/XXX.build/
        3.回到本应用，点击“选择文件”，打开Link Map文件
        4.点击“开始”，解析Link Map文件
        5.点击“输出文件”，得到解析后的Link Map文件
        6. * 输入目标文件的关键字(例如：libIM)，然后点击“开始”。实现搜索功能
        7. * 勾选“分组解析”，然后点击“开始”。实现对不同库的目标文件进行分组
        """
    }
    
    @IBAction func chooseFileButtonClicked(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.resolvesAliases = false
        panel.canChooseFiles = true
        panel.begin { (result) in
            guard result == .OK, let document = panel.urls.first else { return }
            self.filePathTextField.stringValue = document.path
            self.linkMapFileURL = document
        }
    }
    
    @IBAction func startAnalyzeButtonClicked(_ sender: Any) {
        guard let fileURL = linkMapFileURL, FileManager.default.fileExists(atPath: fileURL.path)
            else { return showAlert(with: "请选择正确的Link Map文件路径") }
        
        let isGroup = groupButton.state == .on
        let searchKey = keywordsSearchField.stringValue
        DispatchQueue.global().async {
            do {
                let content = try String(contentsOf: fileURL, encoding: .macOSRoman)
                guard self.checkContent(content) else {
                    return DispatchQueue.main.async { self.showAlert(with: "Link Map文件格式有误") }
                }
                
                DispatchQueue.main.async {
                    self.indicator.isHidden = false
                    self.indicator.startAnimation(self)
                }
                
                let symbolMap = self.symbolMap(fromContent: content)
                let sortedSymbols = symbolMap.values.sorted(by: { $0.size > $1.size })
                let result: String
                if isGroup {
                    result = self.buildCombinationResult(with: sortedSymbols, searchKey: searchKey)
                } else {
                    result = self.buildResult(with: sortedSymbols, searchKey: searchKey)
                }
                
                DispatchQueue.main.async {
                    self.resultTextView.string = result
                    self.indicator.isHidden = true
                    self.indicator.stopAnimation(self)
                }
            } catch {
                print(error)
            }
        }
    }
    
    @IBAction func outputButtonClicked(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.resolvesAliases = false
        panel.canChooseFiles = false
        panel.message = "请选择LPLinkMap.txt文件的保存位置"
        panel.begin { (result) in
            guard result == .OK, let document = panel.urls.first else { return }
            let path = document.path + "/LPLinkMap.txt"
            do {
                try self.resultTextView.string.write(toFile: path, atomically: true, encoding: .utf8)
            } catch {
                print(error)
            }
        }
    }
    
    private func symbolMap(fromContent content: String) -> [String: LPSymbol] {
        var map: [String: LPSymbol] = [:]
        // 符号文件列表
        let lines = content.components(separatedBy: "\n")
        var reachFiles = false
        var reachSymbols = false
        var reachSections = false
        for line in lines {
            if line.hasPrefix("#") {
                if line.hasPrefix("# Object files:") {
                    reachFiles = true
                } else if line.hasPrefix("# Sections:") {
                    reachSections = true
                } else if line.hasPrefix("# Symbols:") {
                    reachSymbols = true
                }
            } else {
                if reachFiles == true && reachSections == false && reachSymbols == false {
                    if let range = line.range(of: "]") {
                        let start = line.index(range.lowerBound, offsetBy: 1)
                        let symbol = LPSymbol(file: String(line[start..<line.endIndex]))
                        map[String(line[line.startIndex..<start])] = symbol
                    }
                } else if reachFiles == true && reachSections == true && reachSymbols == true {
                    let symbols = line.components(separatedBy: "\t")
                    if symbols.count == 3 {
                        let keyAndName = symbols[2]
                        let size = strtoul(symbols[1], nil, 16)
                        if let range = keyAndName.range(of: "]") {
                            let end = keyAndName.index(range.lowerBound, offsetBy: 1)
                            if let symbol = map[String(keyAndName[keyAndName.startIndex..<end])] {
                                symbol.size += size
                            }
                        }
                    }
                }
            }
        }
        return map
    }
    
    private func buildResult(with symbols: [LPSymbol], searchKey: String) -> String {
        var result = "文件大小\t文件名称\r\n\r\n"
        var totalSize: UInt = 0
        
        for symbol in symbols {
            if searchKey.count > 0 {
                if symbol.file.contains(searchKey) {
                    symbol.append(to: &result)
                    totalSize += symbol.size
                }
            } else {
                symbol.append(to: &result)
                totalSize += symbol.size
            }
        }
        result += String(format: "\r\n总大小: %.2fM\r\n", (Float(totalSize) / 1024.0 / 1024.0))
        return result
    }
    
    private func buildCombinationResult(with symbols: [LPSymbol], searchKey: String) -> String {
        var result = "库大小\t库名称\r\n\r\n"
        var totalSize: UInt = 0
        var combinationMap: [String: LPSymbol] = [:]
        
        for symbol in symbols {
            if let name = symbol.file.components(separatedBy: "/").last
                , name.hasSuffix(")")
                , let range = name.range(of: "(") {
                let component = String(name[name.startIndex..<range.lowerBound])
                if let combinationSymbol = combinationMap[component] {
                    combinationSymbol.file = component
                    combinationSymbol.size += symbol.size
                } else {
                    let combinationSymbol = LPSymbol(file: component)
                    combinationSymbol.size += symbol.size
                    combinationMap[component] = combinationSymbol
                }
            } else {
                // symbol可能来自app本身的目标文件或者系统的动态库，在最后的结果中一起显示
                combinationMap[symbol.file] = symbol
            }
        }
        
        let combinationSymbols = combinationMap.values
        let sortedSymbols = combinationSymbols.sorted(by: { $0.size > $1.size })
        for symbol in sortedSymbols {
            if searchKey.count > 0 {
                if symbol.file.contains(searchKey) {
                    symbol.append(to: &result)
                    totalSize += symbol.size
                }
            } else {
                symbol.append(to: &result)
                totalSize += symbol.size
            }
        }
        result += String(format: "\r\n总大小: %.2fM\r\n", (Float(totalSize) / 1024.0 / 1024.0))
        return result
    }
    
    private func checkContent(_ content: String) -> Bool {
        return content.contains("# Path:") && content.contains("# Object files:") && content.contains("# Symbols:")
    }
    
    private func showAlert(with text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.addButton(withTitle: "确定")
        alert.beginSheetModal(for: view.window!, completionHandler: nil)
    }
    
    private class LPSymbol {
        var file: String   // 文件
        var size: UInt = 0 // 大小
        
        init(file: String) {
            self.file = file
        }
        
        func append(to str: inout String) {
            let sizeString: String
            let K = Float(size) / 1024.0
            let M = K / 1024.0
            if M > 1 {
                sizeString = String(format: "%.2fM", M)
            } else {
                sizeString = String(format: "%.2fK", K)
            }
            let fileName = file.components(separatedBy: "/").last ?? file

            str += "\(sizeString)\t\(fileName)\r\n"
        }
    }
}
