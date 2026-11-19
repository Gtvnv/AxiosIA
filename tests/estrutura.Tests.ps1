# Testes de exemplo de estrutura e conteudo fixo do repositorio real.
# Requisitos: 1.5, 2.2, 2.3, 2.4, 4.1, 6.1, 7.5, 10.1, 12.1
BeforeAll {
    $script:Raiz = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:Raiz 'scripts/validar.ps1') -Raiz $script:Raiz

    function Read-Arquivo([string]$Relativo) {
        Get-Content -LiteralPath (Join-Path $script:Raiz $Relativo) -Raw -Encoding UTF8
    }
}

Describe 'Estrutura do repositorio' {
    It 'tem a pasta <_>' -ForEach @('docs', 'materiais/mapa-mental', 'materiais/slides', 'materiais/prints-chat', 'scripts', 'tests') {
        Test-Path -LiteralPath (Join-Path $script:Raiz $_) -PathType Container | Should -BeTrue
    }

    It 'tem arquivo versionavel (.gitkeep ou conteudo) em <_>' -ForEach @('docs', 'materiais/mapa-mental', 'materiais/slides', 'materiais/prints-chat', 'scripts') {
        $arquivos = @(Get-ChildItem -LiteralPath (Join-Path $script:Raiz $_) -File -Force)
        $arquivos.Count | Should -BeGreaterThan 0
    }

    It '.gitignore contem o padrao <_>' -ForEach @('.env', '*.pem', '*.key', 'credentials*.json', '.DS_Store', 'Thumbs.db', 'desktop.ini', '*.axios-novo', '*.axios-bak') {
        $linhas = (Read-Arquivo '.gitignore') -split "\r?\n" | ForEach-Object { $_.Trim() }
        $linhas | Should -Contain $_
    }
}

Describe 'Criterios de confianca' {
    BeforeAll { $script:Crit = Read-Arquivo 'docs/criterios-de-confianca.md' }

    It 'tem cinco criterios numerados' {
        ([regex]::Matches($script:Crit, '(?m)^##\s+[1-5]\.\s+\S')).Count | Should -Be 5
    }

    It 'cada criterio tem "Atendido quando" e "Nao atendido quando"' {
        $blocos = [regex]::Split($script:Crit, '(?m)^##\s+(?=[1-5]\.\s)') | Select-Object -Skip 1
        @($blocos).Count | Should -Be 5
        foreach ($b in $blocos) {
            $b | Should -Match 'Atendido quando'
            $b | Should -Match 'Não atendido quando'
        }
    }

    It 'contem os nomes dos cinco criterios' -ForEach @(
        'Autoria identificável', 'Instituição ou editora reconhecida', 'Data de publicação', 'Referências verificáveis', 'Acesso público') {
        $script:Crit | Should -Match ([regex]::Escape($_))
    }
}

Describe 'Checklist de qualidade' {
    It 'tem exatamente seis itens "- [ ]"' {
        $t = Read-Arquivo 'docs/checklist-qualidade.md'
        ([regex]::Matches($t, '(?m)^\s*- \[ \] ')).Count | Should -Be 6
    }
}

Describe 'Evolucoes' {
    It 'lista a evolucao "<_>"' -ForEach @('Fontes em outro idioma', 'Quiz e glossário', 'Áudio em formato podcast', 'Comparação entre escolas de pensamento') {
        (Read-Arquivo 'docs/evolucoes.md') | Should -Match ('(?m)^##\s+' + [regex]::Escape($_) + '\s*$')
    }

    It 'tem exatamente quatro evolucoes' {
        ([regex]::Matches((Read-Arquivo 'docs/evolucoes.md'), '(?m)^##\s+\S')).Count | Should -Be 4
    }
}

Describe 'Roteiro manual' {
    BeforeAll { $script:Roteiro = Read-Arquivo 'docs/roteiro-manual.md' }

    It 'tem o passo <_>' -ForEach (1..9) {
        $script:Roteiro | Should -Match ('(?m)^' + $_ + '\.\s+\*\*')
    }

    It 'tem exatamente 9 passos numerados' {
        ([regex]::Matches($script:Roteiro, '(?m)^\d+\.\s+\*\*')).Count | Should -Be 9
    }

    It 'passos aparecem em ordem crescente' {
        $nums = [regex]::Matches($script:Roteiro, '(?m)^(\d+)\.\s+\*\*') | ForEach-Object { [int]$_.Groups[1].Value }
        ($nums -join ',') | Should -Be '1,2,3,4,5,6,7,8,9'
    }
}

Describe 'Perguntas candidatas' {
    It 'tem ao menos 5 perguntas candidatas' {
        $t = Read-Arquivo 'docs/registro-de-perguntas.md'
        $idx = $t.IndexOf('## Perguntas candidatas')
        $idx | Should -BeGreaterOrEqual 0
        $secao = $t.Substring($idx)
        ([regex]::Matches($secao, '(?m)^\d+\.\s+\S')).Count | Should -BeGreaterOrEqual 5
    }
}

Describe 'README' {
    BeforeAll { $script:Readme = Read-Arquivo 'README.md' }

    It 'tem as cinco secoes obrigatorias na ordem' {
        $faltantes = @(Find-SecoesFaltantes -TextoReadme $script:Readme)
        $faltantes | Should -BeNullOrEmpty
    }

    It 'secao "Tema e objetivo" contem "(proposto)"' {
        $m = [regex]::Match($script:Readme, '(?ms)^##\s+(?:\d+\.\s*)?Tema e objetivo\s*$(.*?)(?=^#{1,2}\s|\z)')
        $m.Success | Should -BeTrue
        $m.Groups[1].Value | Should -Match ([regex]::Escape('(proposto)'))
    }
}
