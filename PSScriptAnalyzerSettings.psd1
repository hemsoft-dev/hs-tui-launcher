@{
    Severity = @('Error', 'Warning')
    IncludeDefaultRules = $true
    ExcludeRules = @(
        # These command-line tools intentionally write human-facing status directly to the host.
        'PSAvoidUsingWriteHost',
        # Git attributes, not BOMs, define repository encodings for cross-platform scripts.
        'PSUseBOMForUnicodeEncodedFile'
    )
}
