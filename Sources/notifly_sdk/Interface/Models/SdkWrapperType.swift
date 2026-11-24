/// Identifies a wrapper integration in SDK metadata.
///
/// Pass a case's raw value to `Notifly.setSdkType(type:)`. Raw values are integration
/// identifiers and must remain stable across wrapper and native SDK versions.
public enum SdkWrapperType: String {

    /// The React Native wrapper, identified by the raw value `react_native`.
    case react_native

    /// The Flutter wrapper, identified by the raw value `flutter`.
    case flutter
}
