macOS background app. in System Preferences...>Desktop & Dock>Mission Control, disable "When switching to an application, switch Spaces..."

run Choose Switcher. Enable Accessibility in System Preferences...>Privacy & Security>Accessibility. run Choose Switcher.

at some point, you should Allow Choose Switcher access to System Events. you will only be asked once.

when switching apps, one of three things will happen:

  1. nothing happens because there is an open window for that app on screen.
  2. there are no open windows for that app on screen and a pop-up window appears giving three options:
       1. Always Switch
       2. Stay Here
       3. Just Once
     selectiong the first choice with switch to a Space that was the last active window of the app. the second choice and the Space will not change. In either case that preference is stored for that app. the last option will switch to a Space with open windows for that app but will not record the preference.
  4. The Space will switch or not according to the preference for the app

to edit these preferences, open a second Choose Switcher. Or in Services menu of any app, select Services>Open Choose Switcher Settings. all preferences can be deleted with defaults read ~/Library/Preferences/com.entonos.ChooseSwitcher.plist 
