# Premiere Versions

**Less risk of losing your work. More peace of mind for every edit.**

Premiere Versions is a small macOS companion for Adobe Premiere Pro. It keeps a history of saved project files, so an accidental overwrite, a broken project or a change you regret does not have to mean starting over.

Its purpose is simple: **help protect important edits with deliberate version saves and automatic backup checkpoints.** Keeping those copies organized makes it easier to find a useful point to return to.

## A safety net for your projects

- **Save important milestones.** Keep a numbered copy before a major change, a client revision or a new direction. Add a short comment so you remember what changed.
- **Keep backups in the background.** In Auto mode, it watches projects while Premiere Pro is running and keeps recent, hourly and daily checkpoints. New automatic discovery starts with projects created within the last 48 hours. Enrolled projects remain protected after that window.
- **Find your way back.** Manual versions have readable names and comments; backup names include the project, checkpoint type and time.
- **Keep your archive manageable.** Older automatic backups rotate. Your manual versions stay until you decide to remove them. Original project files and Premiere’s own Auto-Saves are left untouched.

## Get started

1. Download the **DMG installer** from [Releases](https://github.com/pewakkk/premiere_versions/releases/latest), open it and **drag Premiere Versions.app onto Applications**. Open the app from Applications, then eject the installer.
2. Choose your Premiere project and allow access to the folders you want to use. Choose Auto in the Backups panel.
3. Save your latest changes in Premiere Pro with **Command+S**.
4. With Premiere Pro active, press **Option+S**, choose a version number, then press Return. Add an optional comment and press Return again to keep the copy.

The shortcut can be changed in Settings. You can also open the utility from its menu bar icon or the Dock.

## Which projects get automatic backups?

New automatic discovery uses the **file creation date within the last 48 hours**, not the last edit date. The project you explicitly select is protected regardless of age. Older unrelated projects do not create new archive folders. If creation time is unavailable, an untracked file is skipped. Projects already enrolled, including existing managed backup archives, continue to be backed up afterwards.

**No internet connection is needed for project discovery or copying.** The next scan can find projects created during an offline period, as long as they are still within the 48-hour window. The app must be running to monitor changes. Manual numbered saves remain available for projects of any age.

## What is protected?

Premiere Versions copies the **project file already saved on disk**. It cannot capture edits you have not saved in Premiere. Copies do not include your footage, audio or other linked media.

Keep your media backed up too. For protection against a drive failure, choose a backup location on a different drive.

## Make it yours

Choose English or Russian, your save locations and a built-in or custom icon. Your choices stay with you when you update.

The app quietly checks for updates at launch and every six hours. Open the version label and use **Check updates** any time; you choose when to install. You can hide the Dock icon and keep the app in the menu bar instead.

## How backup history works

A first copy is made as soon as a stable saved project is found. Later changed states are copied no more often than once every **five minutes**. The archive keeps **10 recent different states**, **12 hourly checkpoints** and **5 daily checkpoints**. Checkpoints can share one physical file when the project has not changed, so an idle project does not fill your archive with duplicates.

Completed copies are checked before old managed copies are removed. Original files and unrelated files are never rotated. Projects with the same name from different locations receive separate folders such as `Project`, `Project_1` and `Project_2`.

The optional **latest Premiere autosave** switch keeps one matching file from the project's neighboring `Adobe Premiere Pro Auto-Save` folder. This copy has its own subfolder, separate from the utility's history. Premiere's original autosaves remain untouched.

## Choose how protection runs

**Auto** runs backups while Premiere Pro is open, including when it is minimized. Closing Premiere pauses the backup timer and file monitoring; a copy already in progress is completed safely. **Always** keeps monitoring while the utility is running. **Off** leaves manual backup creation available.

The backup panel shows your selected project's latest copy and a button to reveal it in Finder. **Create backup now** checks only that project and can save a changed state before the automatic five-minute interval; identical content is not duplicated. Hover over **Details** for retention information and the optional Premiere autosave mirror.

## Background activity

New installations use the **menu bar without a Dock icon**. Click its icon to open the window; right-click for Settings, Backups, backup modes, updates and **Quit completely**. Existing icon choices stay saved when updating.

With **Background activity** on, quitting from Dock or with Command+Q hides the window and keeps the utility in the menu bar. Auto backups continue while Premiere Pro is running, and the shortcut works while Premiere Pro is active. Opening the utility restores your preferred icon locations. Use **Quit completely** in the menu bar for a full exit.

With Background activity off, quitting stops the utility and its helper. The shortcut and automatic launch remain unavailable until you open it manually. **Launch with Premiere Pro** is available only with background activity enabled. macOS may ask you to allow background activity.

At least one icon location stays enabled. Hiding the Dock icon keeps the menu bar route available.

## A quieter interface

Essential settings stay visible. Hover over folder locations or appearance to unfold them, or follow a shortcut to Backups, keyboard shortcuts or version information. Panels open on hover and close after you leave; Escape or a click outside closes them immediately. The compact **En/Ru** button switches languages with one click and remembers your choice.

## Latest improvements

- **Simpler settings.** Essential controls stay visible; folder locations, appearance and backup details unfold on hover. Panels share consistent timing, larger targets and a quick route back to Settings.
- **Background activity you control.** Quitting from Dock or with Command+Q keeps protection in the menu bar when enabled. Quit completely from the menu bar, or disable background activity to stop all background functions after quitting.
- **Useful menu bar controls.** Open Settings and Backups, change backup mode, check for updates or quit completely.
- **Updates beside the version.** Update status and the notification dot now live with version information. Help focuses on protecting and finding your work.
- **One-click language switching.** A compact En/Ru button remembers your choice. English and Russian interface coverage has been checked.
- General improvements to panel placement, control dragging, switch appearance and interface transitions.

## Your work stays yours

Projects and backups stay in the folders you choose. Project files, comments and folder paths are not uploaded by the app. Update checks contact GitHub to look for new releases.

---

Want to build or contribute? See [development notes](DEVELOPMENT.md). For most people, the ready-to-use app in [Releases](https://github.com/pewakkk/premiere_versions/releases/latest) is all you need.
