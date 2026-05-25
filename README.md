Spaces, screens and switching apps on macOS is annoying. No combination of settings achieve something useful for me.

This is useful since some apps (mail, activity monitor, ...) i do have pinned to certain Spaces, while other apps (terminal, xcode, safari, ...) have multiple open windows and i don't want to jump to the Space with the last used window since i probably want to open a new window instead. a Service is provided (Undo Choose Switcher) which in this case, would jump to the Space with the last used window (actually it doesn't). Similarily if you switch to an app and it switches Spaces, the same Service would transport you back to the previous Space. Another example is if in Terminal, switch to Mail and then undo will take you back to Terminal. regardless Terminal will be activated. if there are no visible Terminal windows another undo will switch you to the last used Terminal (it doesn't). i expect only AppleScript can specify which windows in each app to focus and it would be a mess for permissions.




Or that was the idea...



Choose Switcher is a macOS background app. in System Preferences...>Desktop & Dock>Mission Control, disable "When switching to an application, switch Spaces..."

run Choose Switcher. Enable Accessibility in System Preferences...>Privacy & Security>Accessibility. run Choose Switcher.

at some point, you should Allow Choose Switcher access to System Events. you will only be asked once.

when switching apps, one of three things will happen:

  1. nothing happens because there is an open window for that app on screen.
  2. there are no open windows for that app on screen and a pop-up window appears giving three options:
       1. Always Switch
       2. Stay Here
       3. Just Once
          
     selecting the first choice will switch to a Space that was the last active window of the app. the second choice and the Space will not change. In either case that preference is stored for that app. the last option will switch to a Space with open windows for that app but will not record the preference.
  4. The Space will switch or not according to the preference for the app

to edit these preferences, open a second Choose Switcher. Or in Services menu of any app, select Services>Open Choose Switcher Settings. all preferences can be deleted with defaults read ~/Library/Preferences/com.entonos.ChooseSwitcher.plist 

