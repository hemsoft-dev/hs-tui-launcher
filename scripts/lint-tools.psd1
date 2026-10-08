@{
    MarkdownlintCli2 = @{ Version = '0.23.3' }
    PSScriptAnalyzer = @{
        Version = '1.24.0'
        Uri = 'https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/1.24.0'
        Sha256 = 'e86c97d44bb1bc8a1de35e753b85ea1d938f6f9f881639a181507e079bca4556'
    }
    ShellCheck = @{
        Version = '0.11.0'
        Assets = @{
            # Windows ARM64 is intentionally absent; the scripts reject it rather than assume x64 emulation.
            'windows-x64' = @{ Name = 'shellcheck-v0.11.0.zip'; Sha256 = '8a4e35ab0b331c85d73567b12f2a444df187f483e5079ceffa6bda1faa2e740e' }
            'linux-x64' = @{ Name = 'shellcheck-v0.11.0.linux.x86_64.tar.gz'; Sha256 = 'b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6' }
            'linux-arm64' = @{ Name = 'shellcheck-v0.11.0.linux.aarch64.tar.gz'; Sha256 = '68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc' }
            'macos-x64' = @{ Name = 'shellcheck-v0.11.0.darwin.x86_64.tar.gz'; Sha256 = 'c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51' }
            'macos-arm64' = @{ Name = 'shellcheck-v0.11.0.darwin.aarch64.tar.gz'; Sha256 = '339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f' }
        }
    }
    Actionlint = @{
        Version = '1.7.12'
        Assets = @{
            'windows-x64' = @{ Name = 'actionlint_1.7.12_windows_amd64.zip'; Sha256 = '6e7241b51e6817ea6a047693d8e6fed13b31819c9a0dd6c5a726e1592d22f6e9' }
            'windows-arm64' = @{ Name = 'actionlint_1.7.12_windows_arm64.zip'; Sha256 = 'cadcf7ea4efe3a68728893813643cebe1185e5b1d4be5b96245f65c9a4d5ea41' }
            'linux-x64' = @{ Name = 'actionlint_1.7.12_linux_amd64.tar.gz'; Sha256 = '8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8' }
            'linux-arm64' = @{ Name = 'actionlint_1.7.12_linux_arm64.tar.gz'; Sha256 = '325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6' }
            'macos-x64' = @{ Name = 'actionlint_1.7.12_darwin_amd64.tar.gz'; Sha256 = '5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644' }
            'macos-arm64' = @{ Name = 'actionlint_1.7.12_darwin_arm64.tar.gz'; Sha256 = 'aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f' }
        }
    }
}
