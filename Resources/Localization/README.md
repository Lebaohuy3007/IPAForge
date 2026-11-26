# Localization layout

- `Localizable.xcstrings` is the single catalog referenced by the Xcode target.
- `en.lproj/Localizable.xcstrings` and `vi.lproj/Localizable.xcstrings` keep the language folders ready for localized resource organization and mirror the catalog contents.
- When adding or changing a translation, edit the catalog at the directory root, then refresh the two language mirrors.

The catalog contains English and Vietnamese values. The app selects Vietnamese or English at runtime from the App Store region and the saved language preference in `AppEnvironment`.
