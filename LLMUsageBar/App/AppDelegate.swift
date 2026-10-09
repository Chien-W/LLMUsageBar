import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static private(set) var shared: AppDelegate?
    
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    
    private var eventMonitor: Any?
    private var lastCloseTimestamp: TimeInterval = 0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // 关键：构建标准的 macOS 系统菜单链（包含 Edit -> Copy/Paste 等操作）
        // 彻底解决在 LSUIElement 菜单栏程序中 Cmd+V, Cmd+C, Cmd+A, Cmd+Z 无法响应的问题！
        setupStandardMainMenu()
        
        // 设置为后台常驻模式，不占用 Dock 栏
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusItem()
        setupPopover()
    }
    
    /// 注入带有标准编辑快捷键的系统菜单
    private func setupStandardMainMenu() {
        let mainMenu = NSMenu()
        
        // App 顶级菜单
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于 AI 用量监控", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出", action: #selector(terminateApp), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // Edit 菜单（关键：提供系统的 Cut, Copy, Paste, Select All 等快捷键响应链）
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        
        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(undoItem)
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        
        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        editMenu.addItem(cutItem)
        editMenu.addItem(copyItem)
        editMenu.addItem(pasteItem)
        editMenu.addItem(selectAllItem)
        
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        updateStatusItemTitle()
    }
    
    private func setupPopover() {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentSize = NSSize(width: 380, height: 510)
        pop.contentViewController = NSHostingController(rootView: MenuBarView())
        pop.delegate = self
        self.popover = pop
    }
    
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }
    
    func togglePopover() {
        // 防止点击菜单栏图标关闭时因时序问题立即重新打开
        if ProcessInfo.processInfo.systemUptime - lastCloseTimestamp < 0.25 {
            return
        }
        
        guard let pop = popover else { return }
        
        if pop.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }
    
    func showPopover() {
        guard let button = statusItem?.button, let pop = popover else { return }
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // 激活应用并聚焦，确保输入框可以获得键盘焦点并响应快捷键
        NSApp.activate(ignoringOtherApps: true)
        startEventMonitor()
    }
    
    func closePopover() {
        guard let pop = popover, pop.isShown else { return }
        stopEventMonitor()
        lastCloseTimestamp = ProcessInfo.processInfo.systemUptime
        pop.performClose(nil)
    }
    
    private func startEventMonitor() {
        stopEventMonitor()
        // 监听全局鼠标点击事件（桌面、其他窗口、菜单栏空白处等）
        // 当用户点击弹窗外部的任何地方时，立即关闭 popover
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopover()
            }
        }
    }
    
    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    // MARK: - NSPopoverDelegate
    func popoverDidClose(_ notification: Notification) {
        stopEventMonitor()
        lastCloseTimestamp = ProcessInfo.processInfo.systemUptime
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "AI 用量监控 (多账号版)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "立即刷新全部", action: #selector(triggerRefresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "添加新账号...", action: #selector(openAddAccount), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "管理账号与设置...", action: #selector(openAccountsTab), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(terminateApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func triggerRefresh() {
        Task { @MainActor in
            await AppState.shared.refreshAll()
        }
    }
    
    @objc private func openAddAccount() {
        Task { @MainActor in
            AppState.shared.selectedTab = .accounts
            AppState.shared.isAddingAccount = true
            if let pop = popover, !pop.isShown {
                showPopover()
            }
        }
    }
    
    @objc private func openAccountsTab() {
        Task { @MainActor in
            AppState.shared.selectedTab = .accounts
            if let pop = popover, !pop.isShown {
                showPopover()
            }
        }
    }
    
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    
    @objc private func terminateApp() {
        NSApplication.shared.terminate(nil)
    }
    
    func updateStatusItemTitle() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }
            
            let state = AppState.shared
            let mode = ConfigManager.shared.statusDisplayMode
            let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "LLM Usage Monitor")
            image?.isTemplate = true
            button.image = image
            
            switch mode {
            case .iconOnly:
                button.title = ""
            case .accountCount:
                let activeCount = state.accounts.filter { $0.isEnabled }.count
                button.title = activeCount > 0 ? " \(activeCount)" : ""
            case .connectionDot:
                let anyConnected = state.statuses.values.contains { $0.isConnected }
                button.title = anyConnected ? " ●" : " ○"
            }
        }
    }
}
