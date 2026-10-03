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
            'windows-x64' = @{ Name = 'shellcheck-v0.11.0.zip'; Sha256 = '8a4e35ab0b331c85d73567b12f2a444df187f483e5079ceffa6bda1faa2e740e' }
            'linux-x64' = @{ Name = 'shellcheck-v0.11.0.linux.x86_64.tar.gz'; Sha256 = 'b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6' }
            'linux-arm64' = @{ Name = 'shellcheck-v0.11.0.linux.aarch64.tar.gz'; Sha256 = '68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc' }
            'macos-x64' = @{ Name = 'shellcheck-v0.11.0.darwin.x86_64.tar.gz'; Sha256 = 'c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51' }
            'macos-arm64' = @{ Name = 'shellcheck-v0.11.0.darwin.aarch64.tar.gz'; Sha256 = '339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f' }
        }
    }
    Actionlint = @{
        Version = '1.7.7'
        Assets = @{
            'windows-x64' = @{ Name = 'actionlint_1.7.7_windows_amd64.zip'; Sha256 = '7f12f1801bca3d480d67aaf7774f4c2a6359a3ca8eebe382c95c10c9704aa731' }
            'windows-arm64' = @{ Name = 'actionlint_1.7.7_windows_arm64.zip'; Sha256 = '76e9514cfac18e5677aa04f3a89873c981f16a2f2353bb97372a86cd09b1f5a8' }
            'linux-x64' = @{ Name = 'actionlint_1.7.7_linux_amd64.tar.gz'; Sha256 = '023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757' }
            'linux-arm64' = @{ Name = 'actionlint_1.7.7_linux_arm64.tar.gz'; Sha256 = '401942f9c24ed71e4fe71b76c7d638f66d8633575c4016efd2977ce7c28317d0' }
            'macos-x64' = @{ Name = 'actionlint_1.7.7_darwin_amd64.tar.gz'; Sha256 = '28e5de5a05fc558474f638323d736d822fff183d2d492f0aecb2b73cc44584f5' }
            'macos-arm64' = @{ Name = 'actionlint_1.7.7_darwin_arm64.tar.gz'; Sha256 = '2693315b9093aeacb4ebd91a993fea54fc215057bf0da2659056b4bc033873db' }
        }
    }
}
