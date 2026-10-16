//
//  iOSAccessoryView.swift
//  
//  Implements an inputAccessoryView for the iOS terminal for common operations
//
//  Created by Miguel de Icaza on 5/9/20.
//
#if os(iOS) || os(visionOS)

import Foundation
import UIKit

/**
 * This class provides an input accessory for the terminal on iOS, you can access this via the `inputAccessoryView`
 * property in the `TerminalView` and casting the result to `TerminalAccessory`.
 *
 * This class surfaces some state that the terminal might want to poke at, you should at least support the following
 * properties;
 * `controlModifer` should be set if the control key is pressed
 */
public class TerminalAccessory: UIInputView, UIInputViewAudioFeedback {
    /// This points to an instanace of the `TerminalView` where events are sent
    public weak var terminalView: TerminalView?
    weak var terminal: Terminal?
    var controlButton: UIButton?
    /// This tracks whether the "control" button is turned on or not
    public var controlModifier: Bool = false {
        didSet {
            controlButton?.isSelected = controlModifier
        }
    }
    
    var touchButton: UIButton!
    var keyboardButton: UIButton!
    
    var views: [UIView] = []
    
    public init (frame: CGRect, inputViewStyle: UIInputView.Style, container: TerminalView)
    {
        self.terminalView = container
        self.terminal = terminalView?.getTerminal()
        super.init (frame: frame, inputViewStyle: inputViewStyle)
        allowsSelfSizing = true
    }
    
    public override var bounds: CGRect {
        didSet {
            setupUI ()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    #if os(iOS)
    // Override for UIInputViewAudioFeedback
    public var enableInputClicksWhenVisible: Bool { true }
    #endif
    
    func clickAndSend (_ data: [UInt8])
    {
        #if os(iOS)
        UIDevice.current.playInputClick()
        #endif
        terminalView?.send (data)
    }

    func clickAndInsertText (_ text: String)
    {
        #if os(iOS)
        UIDevice.current.playInputClick()
        #endif
        terminalView?.insertTextFromAccessory(text)
    }
    
    @objc func esc (_ sender: AnyObject) { clickAndSend ([0x1b]) }
    @objc func tab (_ sender: AnyObject) { clickAndSend ([0x9]) }
    @objc func tilde (_ sender: AnyObject) { clickAndInsertText ("~") }
    @objc func pipe (_ sender: AnyObject) { clickAndInsertText ("|") }
    @objc func slash (_ sender: AnyObject) { clickAndInsertText ("/") }
    @objc func dash (_ sender: AnyObject) { clickAndInsertText ("-") }
    @objc func f1 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[0]) }
    @objc func f2 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[1]) }
    @objc func f3 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[2]) }
    @objc func f4 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[3]) }
    @objc func f5 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[4]) }
    @objc func f6 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[5]) }
    @objc func f7 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[6]) }
    @objc func f8 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[7]) }
    @objc func f9 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[8]) }
    @objc func f10 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[9]) }
    
    @objc
    func ctrl (_ sender: UIButton)
    {
        controlModifier.toggle()
    }

    // Controls the timer for auto-repeat
    var repeatCommand: (() -> ())? = nil
    var repeatTimer: Timer?
    var repeatTask: Task<(), Never>?
    
    func startTimerForKeypress (repeatKey: @escaping () -> ())
    {
        repeatKey ()
        repeatCommand = repeatKey
        
        repeatTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !(repeatTask?.isCancelled ?? true) else { return }
            let rc = self.repeatCommand
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                rc? ()
            }
        }
    }
    
    @objc
    func cancelTimer ()
    {
        repeatTimer?.invalidate()
        repeatCommand = nil
        repeatTimer = nil
        repeatTask?.cancel()
    }
    
    @objc func up (_ sender: UIButton)
    {
        startTimerForKeypress { self.terminalView?.sendKeyUp () }
    }
    
    @objc func down (_ sender: UIButton)
    {
        startTimerForKeypress { self.terminalView?.sendKeyDown () }
    }
    
    @objc func left (_ sender: UIButton)
    {
        startTimerForKeypress { self.terminalView?.sendKeyLeft() }
    }
    
    @objc func right (_ sender: UIButton)
    {
        startTimerForKeypress { self.terminalView?.sendKeyRight() }
    }


    // LFG PATCH 4: the keyboard key hides and shows the keyboard (board
    // `s2-terminal`), instead of swapping in SwiftTerm's alternate key panel.
    // Hidden keeps the terminal first responder with an empty input view, so this
    // row stays on screen above the home indicator (board: 34pt up). iOS 26 sets
    // any non-empty input view on its keyboard backdrop with 16pt above it
    // (measured), so the view is the inset minus that; clear, so the backdrop
    // reads as one panel.
    @objc func toggleInputKeyboard (_ sender: UIButton) {
        guard let tv = terminalView else { return }

        if tv.inputView is HiddenKeyboardView {
            tv.inputView = nil
        } else {
            let inset = window?.safeAreaInsets.bottom ?? 34
            let hidden = HiddenKeyboardView (frame: CGRect (x: 0, y: 0, width: UIScreen.main.bounds.width,
                                                            height: max (1, inset - 16)))
            hidden.backgroundColor = .clear
            tv.inputView = hidden
        }
        UIView.performWithoutAnimation {
            tv.reloadInputViews()
        }
        updateKeyboardKey ()
    }

    func updateKeyboardKey () {
        let open = !(terminalView?.inputView is HiddenKeyboardView)
        keyboardButton?.setImage (Self.keyboardGlyph (open: open), for: .normal)
        keyboardButton?.accessibilityLabel = open ? "Hide keyboard" : "Show keyboard"
    }

    // LFG PATCH 4: the board's keyboard icon (20×16pt, a 26×20 box): the keyboard,
    // then a chevron down while it is up, or up while it is hidden.
    static func keyboardGlyph (open: Bool) -> UIImage {
        let size = CGSize (width: 20, height: 16)
        let k: CGFloat = 20.0 / 26.0
        let dy = (size.height - 20 * k) / 2
        return UIGraphicsImageRenderer (size: size).image { ctx in
            let c = ctx.cgContext
            func p (_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint (x: x * k, y: dy + y * k) }
            c.setStrokeColor (UIColor.white.cgColor)
            c.setLineWidth (1.6 * k)
            c.setLineCap (.round)
            c.addPath (UIBezierPath (roundedRect: CGRect (origin: p (1, 1), size: CGSize (width: 24 * k, height: 12 * k)),
                                     cornerRadius: 2 * k).cgPath)
            for x: CGFloat in [5, 9, 13, 17, 21] {
                c.move (to: p (x, 5))
                c.addLine (to: p (x + 0.01, 5))
            }
            c.move (to: p (7, 9))
            c.addLine (to: p (19, 9))
            if open {
                c.move (to: p (10, 16)); c.addLine (to: p (13, 19)); c.addLine (to: p (16, 16))
            } else {
                c.move (to: p (10, 19)); c.addLine (to: p (13, 16)); c.addLine (to: p (16, 19))
            }
            c.strokePath ()
        }
    }

    @objc func toggleTouch (_ sender: UIButton) {
        terminalView?.allowMouseReporting.toggle()
        touchButton.isSelected = !(terminalView?.allowMouseReporting ?? false)
    }

    var leftViews: [UIView] = []
    var floatViews: [UIView] = []
    var rightViews: [UIView] = []

    // LFG PATCH (see PATCHES.md, patch 4): the S2 key row (lfg board
    // `s2-terminal`). One horizontally scrolling row — esc, tab, ctrl, ⌥, the
    // arrows, | / ~ -, ⌘V and the keyboard switch — instead of upstream's fixed
    // left/right groups and function keys. ctrl and ⌥ are sticky: ⌥ is
    // `TerminalView.metaModifier` (ESC-prefixes the next key), ⌘V is
    // `TerminalView.paste` (bracketed when the app asks for it).
    let keyScroll = KeyRowScrollView()
    let keyBorder = UIView()
    var metaButton: UIButton?
    var keyRow: [UIView] = []

    static let rowHeight: CGFloat = 50
    static let keyHeight: CGFloat = 36
    static let keyGap: CGFloat = 6
    static let rowInset: CGFloat = 8

    @objc func meta (_ sender: UIButton)
    {
        guard let tv = terminalView else { return }
        tv.metaModifier.toggle()
        metaButton?.isSelected = tv.metaModifier
    }

    @objc func pasteFromKey (_ sender: UIButton)
    {
        #if os(iOS)
        UIDevice.current.playInputClick()
        #endif
        terminalView?.paste (nil)
    }

    @objc func metaModifierReset (_ note: Notification)
    {
        metaButton?.isSelected = false
    }

    /**
     * This method setups the internal data structures to setup the UI shown on the accessory view,
     * if you provide your own implementation, you are responsible for adding all the elements to the
     * this view, and flagging some of the public properties declared here.
     */
    public func setupUI ()
    {
        for view in views {
            view.removeFromSuperview()
        }
        views = []
        leftViews = []
        rightViews = []
        floatViews = []
        keyRow.forEach { $0.removeFromSuperview() }
        keyRow = []
        terminalView?.setupKeyboardButtonColors ()

        backgroundColor = UIColor (red: 28/255.0, green: 28/255.0, blue: 30/255.0, alpha: 1)
        keyBorder.backgroundColor = UIColor (red: 44/255.0, green: 44/255.0, blue: 46/255.0, alpha: 1)
        keyScroll.showsHorizontalScrollIndicator = false
        keyScroll.showsVerticalScrollIndicator = false
        keyScroll.alwaysBounceHorizontal = true
        // Keys fire on touch-down; holding their delivery briefly lets a drag
        // scroll the row instead of pressing the key under the finger.
        keyScroll.delaysContentTouches = true
        keyScroll.canCancelContentTouches = true

        keyRow.append (makeS2Key ("esc", #selector(esc)))
        keyRow.append (makeS2Key ("tab", #selector(tab)))
        let controlButton = makeS2Key ("ctrl", #selector(ctrl))
        self.controlButton = controlButton
        keyRow.append (controlButton)
        let metaButton = makeS2Key ("⌥", #selector(meta))
        metaButton.isSelected = terminalView?.metaModifier ?? false
        self.metaButton = metaButton
        keyRow.append (metaButton)
        keyRow.append (makeS2Key ("↑", #selector(up), repeats: true))
        keyRow.append (makeS2Key ("↓", #selector(down), repeats: true))
        keyRow.append (makeS2Key ("←", #selector(left), repeats: true))
        keyRow.append (makeS2Key ("→", #selector(right), repeats: true))
        keyRow.append (makeS2Key ("|", #selector(pipe)))
        keyRow.append (makeS2Key ("/", #selector(slash)))
        keyRow.append (makeS2Key ("~", #selector(tilde)))
        keyRow.append (makeS2Key ("⌘V", #selector(pasteFromKey)))
        touchButton = makeButton ("", #selector(toggleTouch), icon: "hand.draw", isNormal: false)
        // LFG PATCH 3: the mouse-reporting toggle is not offered.
        let keyboardButton = makeS2Key ("", #selector(toggleInputKeyboard), minWidth: 44)
        self.keyboardButton = keyboardButton
        updateKeyboardKey ()
        keyRow.append (keyboardButton)

        NotificationCenter.default.removeObserver (self, name: .terminalViewMetaModifierReset, object: nil)
        NotificationCenter.default.addObserver (self, selector: #selector(metaModifierReset(_:)),
                                                name: .terminalViewMetaModifierReset, object: terminalView)

        keyRow.forEach { keyScroll.addSubview ($0) }
        views = [keyScroll, keyBorder]
        for view in views {
            addSubview (view)
        }
        layoutSubviews ()
    }

    func makeS2Key (_ title: String, _ action: Selector, repeats: Bool = false, minWidth: CGFloat = 40) -> UIButton
    {
        let b = BackgroundSelectedButton (type: .custom)
        let fill = UIColor (red: 58/255.0, green: 58/255.0, blue: 60/255.0, alpha: 1)
        b.color = fill
        b.backgroundColor = fill
        b.layer.cornerRadius = 8
        b.layer.masksToBounds = true
        b.setTitle (title, for: .normal)
        b.setTitleColor (.white, for: .normal)
        b.setTitleColor (.black, for: .selected)
        b.titleLabel?.font = UIFont.monospacedSystemFont (ofSize: 14, weight: .semibold)
        b.contentEdgeInsets = UIEdgeInsets (top: 0, left: 9, bottom: 0, right: 9)
        b.addTarget (self, action: action, for: .touchDown)
        if repeats {
            b.addTarget (self, action: #selector(cancelTimer), for: .touchUpOutside)
            b.addTarget (self, action: #selector(cancelTimer), for: .touchCancel)
            b.addTarget (self, action: #selector(cancelTimer), for: .touchUpInside)
        }
        b.sizeToFit ()
        b.frame.size = CGSize (width: max (minWidth, b.frame.width), height: TerminalAccessory.keyHeight)
        b.accessibilityLabel = title.isEmpty ? "Keyboard" : title
        return b
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
return
        setupUI()
    }

    var _useSmall: Bool {
        get {
            frame.width < 380
        }
    }

    var buttonPad = 4.0
    public override func layoutSubviews() {
        keyBorder.frame = CGRect (x: 0, y: 0, width: bounds.width, height: 0.5)
        keyScroll.frame = bounds
        var x = TerminalAccessory.rowInset
        let y = (bounds.height - TerminalAccessory.keyHeight) / 2
        for key in keyRow {
            key.frame.origin = CGPoint (x: x, y: y)
            x += key.frame.width + TerminalAccessory.keyGap
        }
        keyScroll.contentSize = CGSize (width: x - TerminalAccessory.keyGap + TerminalAccessory.rowInset,
                                        height: bounds.height)
    }

    func makeAutoRepeatButton (_ iconName: String, _ action: Selector) -> UIButton
    {
        let b = makeButton ("", action, icon: iconName)
        b.addTarget(self, action: #selector(cancelTimer), for: .touchUpOutside)
        b.addTarget(self, action: #selector(cancelTimer), for: .touchCancel)
        b.addTarget(self, action: #selector(cancelTimer), for: .touchUpInside)
        return b
    }
    
    func makeButton (_ title: String, _ action: Selector, icon: String = "", isNormal: Bool = true) -> UIButton
    {
        let useSmall = self._useSmall
        let b = BackgroundSelectedButton.init(type: .roundedRect)
        
        TerminalAccessory.styleButton (b)
        b.addTarget(self, action: action, for: .touchDown)
        b.setTitle(title, for: .normal)
        guard let terminalView else {
            return b
        }
        b.color = isNormal ? terminalView.buttonBackgroundColor : terminalView.buttonDarkBackgroundColor
        b.setTitleColor(terminalView.buttonColor, for: .normal)
        b.setTitleColor(terminalView.buttonColor, for: .selected)
        if useSmall {
            b.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        }
        b.backgroundColor = isNormal ? terminalView.buttonBackgroundColor : terminalView.buttonDarkBackgroundColor
        
        if icon != "" {
            if let img = UIImage (systemName: icon, withConfiguration: UIImage.SymbolConfiguration (pointSize: 14.0)) {
                b.setImage(img.withTintColor(terminalView.buttonColor, renderingMode: .alwaysOriginal), for: .normal)
            }
        }
        return b
    }
    
    func makeDouble (_ primary: String, _ secondary: String) -> UIView {
        let b = DoubleButton (frame: CGRect (x: 0, y: 0, width: 20, height: 26))
        b.primaryText = primary
        b.secondaryText = secondary
        return b
    }
    
    // I am not committed to this style, this is just something quick to get going
    static func styleButton (_ b: UIButton)
    {
        b.layer.cornerRadius = 5
        b.layer.masksToBounds = true
        b.layer.shadowOffset = CGSize(width: 0, height: 1.0)
        b.layer.shadowRadius = 0.0
        b.layer.shadowOpacity = 0.35
    }
}


/// LFG PATCH 4: the key row scrolls even when a drag starts on a key.
/// LFG PATCH 4: the empty input view that stands for "keyboard hidden".
final class HiddenKeyboardView: UIView {}

class KeyRowScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

class BackgroundSelectedButton: UIButton {
    
    var color: UIColor?
    
    override var isSelected: Bool {
        didSet {
            // LFG PATCH 4: a latched ctrl/⌥ key turns white (S2 key row).
            self.backgroundColor = isSelected ? .white : color
        }
    }
}
#endif
