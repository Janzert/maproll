/**
 * @description Small app to reset livesplit timer while rerolling factorio map
 * @author janzert
 * @version 1.0
 */

#Requires AutoHotkey v2.0

#Include "Socket.ahk"

class MyError extends Error {

}

class LocalLivesplit {
  static debounce_delay := 305

  __New(settings) {
    this.reset_key := this.PrepKeys(settings.livesplit_local_reset)
    this.start_key := this.PrepKeys(settings.livesplit_local_start)
    this.last_send := A_TickCount
  }

  PrepKeys(hotkey) {
    return RegExReplace(hotkey, "([#!^+<>]*)([\w]{2,})", "$1{$2}")
  }

  Delay() {
    delay := LocalLivesplit.debounce_delay
    next_send := this.last_send + delay
    now := A_TickCount
    if (now < next_send) {
      wait := next_send - now
      wait := wait < delay ? wait : delay
      wait := wait > 0 ? wait : 0
      Sleep(wait)
    }
  }

  Reset() {
    this.Delay()
    Send this.reset_key
    this.last_send := A_TickCount
  }

  Start() {
    this.Delay()
    Send this.start_key
    this.last_send := A_TickCount
  }
}

class NetworkLivesplit {
  __New(settings) {
    this.host := settings.livesplit_network_host
    this.port := settings.livesplit_network_port
    this.socket := false
  }

  Connect() {
    if not this.socket {
      this.socket := Socket.Client(this.host, this.port,
          Socket.TYPE.STREAM, Socket.IPPROTO.TCP)
    }
  }

  Send(line) {
    try {
      this.Connect()
      this.socket.SendText(line . "`n")
    } catch OSError as err {
      this.socket := false
      msg := "Error connecting to network livesplit:`n`n" . err.Message
      throw MyError(msg)
    }
  }

  Reset() {
    this.Send("reset")
  }

  Start() {
    this.Send("startorsplit")
  }
}

class SettingStore {
  static registry_key := "HKCU\Software\FactorioRoller"

  reroll_key := "F12"
  livesplit_method := "Keyboard"
  livesplit_local_reset := "^!Numpad3"
  livesplit_local_start := "Numpad1"
  livesplit_network_host := ""
  livesplit_network_port := 16834

  Load() {
    this.reroll_key := RegRead(SettingStore.registry_key, "reroll_key", "F12")
    stored_method := RegRead(SettingStore.registry_key,
        "livesplit_method", "Keyboard")
    for check in ["Keyboard", "TCP"] {
      if (stored_method == check) {
        this.livesplit_method := stored_method
        break
      }
    }
    this.livesplit_local_reset := RegRead(SettingStore.registry_key,
        "livesplit_local_reset", "!^{Numpad3}")
    this.livesplit_local_start := RegRead(SettingStore.registry_key,
        "livesplit_local_start", "{Numpad1}")
    this.livesplit_network_host := RegRead(SettingStore.registry_key,
        "livesplit_network_host", "")
    this.livesplit_network_port := RegRead(SettingStore.registry_key,
        "livesplit_network_port", 16834)
  }

  Save() {
    RegWrite(this.reroll_key, "REG_SZ", SettingStore.registry_key, "reroll_key")
    RegWrite(this.livesplit_method, "REG_SZ", SettingStore.registry_key,
        "livesplit_method")
    RegWrite(this.livesplit_local_reset, "REG_SZ", SettingStore.registry_key,
        "livesplit_local_reset")
    RegWrite(this.livesplit_local_start, "REG_SZ", SettingStore.registry_key,
        "livesplit_local_start")
    RegWrite(this.livesplit_network_host, "REG_SZ", SettingStore.registry_key,
        "livesplit_network_host")
    RegWrite(this.livesplit_network_port, "REG_DWORD", SettingStore.registry_key,
        "livesplit_network_port")
  }
}

class SettingGUI {
  __New(settings, reroll_control) {
    this.settings := settings
    this.reroll_control := reroll_control
    this.window := Gui("", "Factorio Map Roller", this)
    close_func := ObjBindMethod(this, "Close")
    this.window.OnEvent("Close", close_func)
    this.save_func := ObjBindMethod(this, "TimedSave")
    this.window.AddText("YM+6", "Reroll hotkey:")
    hk_ctrl := this.window.AddHotkey("vreroll_key X+10 YM+0", settings.reroll_key)
    hk_ctrl.OnEvent("Change", "OnChange")
    this.window.AddText("Section XM+0 Y+10", "Livesplit control method:")
    method_ix := settings.livesplit_method == "TCP" ? 2 : 1
    loc_ctrl := this.window.AddDDL(
      "vlivesplit_method X+10 YS-4 Choose" . method_ix,
      ["Keyboard", "TCP"]
    )
    loc_ctrl.OnEvent("Change", "OnChange")
    lsr_text := this.window.AddText("Section XM+0 Y+10", "Livesplit reset key:")
    lsr_ctrl := this.window.AddHotkey("vlivesplit_local_reset X+10 YS-4",
        settings.livesplit_local_reset)
    lsr_ctrl.OnEvent("Change", "OnChange")
    lss_text := this.window.AddText("Section XM+0 Y+10", "Livesplit start key:")
    lss_ctrl := this.window.AddHotkey("vlivesplit_local_start X+10 YS-4",
        settings.livesplit_local_start)
    lss_ctrl.OnEvent("Change", "OnChange")
    loc_ctrl.GetPos(, &loc_y, , &loc_height)
    lsip_y := loc_y + loc_height + 10
    lsip_text := this.window.AddText("Section XM+0 Y" lsip_y, "Livesplit hostname/IP:")
    lsip_ctrl := this.window.AddEdit("vlivesplit_network_host X+10 YS-4",
        settings.livesplit_network_host)
    lsip_ctrl.OnEvent("Change", "OnChange")
    lsp_text := this.window.AddText("Section XM+0 Y+10", "Livesplit port:")
    lsp_ctrl := this.window.AddEdit("vlivesplit_network_port Number X+10 YS-4",
        settings.livesplit_network_port)
    lsp_ctrl.OnEvent("Change", "OnChange")
    this.local_options := [lsr_text, lsr_ctrl, lss_text, lss_ctrl]
    this.network_options := [lsip_text, lsip_ctrl, lsp_text, lsp_ctrl]

    this.test_button := this.window.AddButton("vlivesplit_test Center", "Test livesplit")
    this.test_button.OnEvent("Click", "OnClick")
    this.window.AddText("XM+0 Center", "Test will start livesplit timer and then reset it after 5 seconds.")
    this.SetCtrlAvailability()
  }

  SetCtrlAvailability() {
    local_enabled := True
    if this.settings.livesplit_method == "TCP" {
      local_enabled := False
    }
    for ctrl in this.local_options {
      ctrl.Visible := local_enabled
      ctrl.Enabled := local_enabled
    }
    for ctrl in this.network_options {
      ctrl.Visible := !local_enabled
      ctrl.Enabled := !local_enabled
    }
  }

  Show() {
    this.window.Show()
    this.test_button.Focus()
  }

  Close(guiobj) {
    this.window.Hide()
    this.window.Destroy()
    this.reroll_control.DisableHotkey()
    this.settings.Save()
    ExitApp
  }

  TimedSave() {
    this.settings.Save()
    SetTimer( , 0)
  }

  OnChange(ctrl, info) {
    valid_change := False
    Switch(ctrl.Name) {
      Case "reroll_key":
        if ctrl.Value == "" {
          ctrl.Value := this.settings.reroll_key
        } else if (RegExMatch(ctrl.Value, "[^+!^]") != 0
            and this.settings.reroll_key != ctrl.Value) {
          this.settings.reroll_key := ctrl.Value
          this.reroll_control.UpdateHotkey()
          valid_change := True
        }
      Case "livesplit_method":
        if (this.settings.livesplit_method != ctrl.Text) {
          this.settings.livesplit_method := ctrl.Text
          this.SetCtrlAvailability()
          this.reroll_control.UpdateLivesplit()
          valid_change := True
        }
      Case "livesplit_local_reset":
        if ctrl.Value == "" {
          ctrl.Value := this.settings.livesplit_local_reset
        } else if (RegExMatch(ctrl.Value, "[^+!^]") != 0
            and this.settings.livesplit_local_reset != ctrl.Value) {
          this.settings.livesplit_local_reset := ctrl.Value
          this.reroll_control.UpdateLivesplit()
          valid_change := True
        }
      Case "livesplit_local_start":
        if ctrl.Value == "" {
          ctrl.Value := this.settings.livesplit_local_start
        } else if (RegExMatch(ctrl.Value, "[^+!^]") != 0
            and this.settings.livesplit_local_start != ctrl.Value) {
          this.settings.livesplit_local_start := ctrl.Value
          this.reroll_control.UpdateLivesplit()
          valid_change := True
        }
      Case "livesplit_network_host":
        if (this.settings.livesplit_network_host != ctrl.Text) {
          this.settings.livesplit_network_host := ctrl.Text
          this.reroll_control.UpdateLivesplit()
          valid_change := True
        }
      Case "livesplit_network_port":
        if (ctrl.Text > 0 and ctrl.Text < 65536
            and this.settings.livesplit_network_port != ctrl.Text) {
          this.settings.livesplit_network_port := ctrl.Text
          this.reroll_control.UpdateLivesplit()
          valid_change := True
        }
      Default:
        throw ValueError("Unknown control change event received" . ctrl.Name)
    }
    if (valid_change) {
      SetTimer(this.save_func, 750)
    }
  }

  OnClick(ctrl, info) {
    SetTimer(ObjBindMethod(this.reroll_control, "RunTest"), -1)
  }
}

class RerollControl {
  __New(settings) {
    this.settings := settings
    this.current_hotkey := ""

    this.UpdateLivesplit()
    this.UpdateHotkey()
  }

  UpdateLivesplit() {
    Switch(this.settings.livesplit_method) {
      Case "Keyboard":
        this.livesplit := LocalLivesplit(this.settings)
      Case "TCP":
        this.livesplit := NetworkLivesplit(this.settings)
      Default:
        throw ValueError("Unknown livesplit control method: " . settings.livesplit_method)
    }
  }

  UpdateHotkey() {
    cb_func := ObjBindMethod(this, "HotkeyCallback")
    if this.current_hotkey != "" {
      Hotkey(this.current_hotkey, "Off")
    }
    Hotkey(this.settings.reroll_key, cb_func)
    this.current_hotkey := this.settings.reroll_key
  }

  DisableHotkey() {
    if this.current_hotkey != "" {
      Hotkey(this.current_hotkey, "Off")
      this.current_hotkey := ""
    }
  }

  FindButton() {
    default_color := "0x8E8E8E"
    inter_color := "0x242324"
    active_color := "0xE39827"
    border_color := "0x313031"

    MouseGetPos(&mstart_x, &mstart_y)
    WinGetClientPos(,, &win_width, &win_height, "A")
    mcur_x := mstart_x
    mcur_y := mstart_y
    start_width := win_width * 0.2
    start_height := win_height * 0.2
    if (mcur_x < win_width / 2 and mcur_y < win_height / 2
        and PixelSearch(&_, &_, mcur_x - 5, mcur_y - 5, mcur_x + 5, mcur_y + 5,
                        active_color, 25)) {
      MouseMove(0, 0)
      mcur_x := 0
      mcur_y := 0
      Sleep 100
    }
    if (!PixelSearch(&maptype_left, &maptype_top,
                    0, 0,
                    start_width, start_height,
                    default_color)) {
      throw MyError("Could not find reroll button location`n`n{type_topleft}")
    }
    right_limit := maptype_left + (win_width * 0.5)
    if (!PixelSearch(&inter_x, &inter_y,
                    maptype_left, maptype_top,
                    right_limit, maptype_top,
                    inter_color)) {
      throw MyError("Could not find reroll button location`n`n{inter}")
    }
    right_limit := inter_x + (win_width * 0.3)
    bottom_limit := maptype_top + ((inter_x - maptype_left) / 5)
    if (mcur_y > maptype_top - 5 and mcur_y < bottom_limit
        and mcur_x > inter_x and mcur_x < right_limit
        and PixelSearch(&_, &_, mcur_x - 5, mcur_y - 5, mcur_x + 5, mcur_y + 5,
                        active_color, 25)) {
      MouseMove(0, 0)
      mcur_x := 0
      mcur_y := 0
      Sleep 100
    }
    if (!PixelSearch(&reroll_left, &reroll_top,
                    inter_x, inter_y - 2,
                    right_limit, inter_y + 2,
                    default_color)) {
      throw MyError("Could not find reroll button location`n`n{reroll_left}")
    }
    right_limit := reroll_left + ((reroll_left - maptype_left) / 10)
    bottom_limit := reroll_top + ((reroll_left - maptype_left) / 10)
    if (mcur_y > reroll_top - 5 and mcur_y < bottom_limit + 5
        and mcur_x > reroll_left - 5 and mcur_x < right_limit + 5
        and PixelSearch(&_, &_, mcur_x - 5, mcur_y - 5, mcur_x + 5, mcur_y + 5,
                        active_color, 25)) {
      MouseMove(0, 0)
      mcur_x := 0
      mcur_y := 0
      Sleep 100
    }
    ; Right to Left search for right edge of reroll button
    if (!PixelSearch(&reroll_right, &_,
                    right_limit, reroll_top,
                    reroll_left, reroll_top,
                    default_color)) {
      throw MyError("Could not find reroll button location`n`n{reroll_right}")
    }
    half := (reroll_right - reroll_left) / 2
    center_x := reroll_left + half
    center_y := reroll_top + half
    MouseMove(center_x, center_y)
    Loop 10 {
      Sleep 10
      found_color := PixelGetColor(center_x, reroll_top + (half / 2))
      if (found_color == active_color) {
        break
      }
    }
    if (found_color != active_color) {
      throw MyError("Could not find reroll button location`n`n{active_color}")
    }
    MouseMove(mstart_x, mstart_y)
    return [reroll_left + half, reroll_top + half]
  }

  RunTest() {
    try {
      livesplit := this.livesplit
      livesplit.Reset()
      livesplit.Start()
      Sleep(5000)
      livesplit.Reset()
    } catch MyError as err {
      Msgbox(err.Message, "Error", "OK")
    }
  }

  TriggerReroll() {
    win_class := WinGetClass("A")
    if win_class != "Factorio" {
      MsgBox("Factorio doesn't appear to be the active window.")
      return
    }
    try {
      pos := this.FindButton()
      this.livesplit.Reset()
      this.livesplit.Start()
      Click(pos[1], pos[2])
    } catch MyError as err {
      MsgBox(err.Message, "Error", "OK")
    }
  }

  HotkeyCallback(hotkey_name) {
    this.TriggerReroll()
  }
}

#SingleInstance Force
A_ScriptName := "Factorio Map Roller"
A_IconTip := "Factorio Map Roller"
try {
  TraySetIcon("maproll.ico")
} catch Error as err {
  if (err.Message != "Can't load icon.") {
   throw err
  }
}
if (A_IsCompiled) {
  A_IconHidden := 1
}

settings := SettingStore()
settings.Load()
reroller := RerollControl(settings)
setting_gui := SettingGUI(settings, reroller)
setting_gui.Show()

