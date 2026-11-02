# Premiere Versions

**Less risk of losing your work. More peace of mind for every edit.**

Premiere Versions is a small macOS companion for Adobe Premiere Pro. It keeps a history of saved project files, so an accidental overwrite, a broken project or a change you regret does not have to mean starting over.

Its purpose is simple: **help protect important edits with deliberate version saves and automatic backup checkpoints.** Keeping those copies organized makes it easier to find a useful point to return to.

## A safety net for your projects

- **Save important milestones.** Keep a numbered copy before a major change, a client revision or a new direction. Add a short comment so you remember what changed.
- **Keep backups in the background.** While the app is running and backup monitoring is enabled, it watches saved project files and keeps recent, hourly and daily checkpoints.
- **Find your way back.** Manual versions have readable names and comments; backup names include the project, checkpoint type and time.
- **Keep your archive manageable.** Older automatic backups rotate. Your manual versions stay until you decide to remove them. Original project files and Premiere’s own Auto-Saves are left untouched.

## Get started

1. Download the **DMG installer** from [Releases](https://github.com/pewakkk/premiere_versions/releases/latest), open it and **drag Premiere Versions.app onto Applications**. Open the app from Applications, then eject the installer.
2. Choose your Premiere project and allow access to the folders you want to use. Enable backup monitoring in Settings.
3. Save your latest changes in Premiere Pro with **Command+S**.
4. With Premiere Pro active, press **Option+S**, choose a version number, then press Return. Add an optional comment and press Return again to keep the copy.

The shortcut can be changed in Settings. You can also open the utility from the Dock or enable its optional menu bar icon.

## What is protected?

Premiere Versions copies the **project file already saved on disk**. It cannot capture edits you have not saved in Premiere. Copies do not include your footage, audio or other linked media.

Keep your media backed up too. For protection against a drive failure, choose a backup location on a different drive.

## Make it yours

Choose English or Russian, your save locations and a built-in or custom icon. Your choices stay with you when you update.

The app quietly checks for updates at launch and every six hours. Use **Check updates** in Settings any time; you choose when to install. You can hide the Dock icon and keep the app in the menu bar instead.

## What’s new in 4.5

- **Project selection:** a dedicated screen, clearer navigation and reliable handling of missing or moved projects.
- **Icons and appearance:** a compact picker, two new built-in styles, removable custom icons and the option to hide the Dock icon.
- **Keyboard shortcuts:** clearer setup and English key labels when recording a shortcut.
- **Updates:** quiet checks at launch and every six hours, with subtle indicators. You choose when to install.
- **Interface refinements:** softer blur transitions, cleaner help controls and short-term memory for the Settings scroll position.
- **Optimization:** reduced background activity, fewer repeated archive checks and no animation polling while the utility is hidden.

## Your work stays yours

Projects and backups stay in the folders you choose. Project files, comments and folder paths are not uploaded by the app. Update checks contact GitHub to look for new releases.

---

Want to build or contribute? See [development notes](DEVELOPMENT.md). For most people, the ready-to-use app in [Releases](https://github.com/pewakkk/premiere_versions/releases/latest) is all you need.
