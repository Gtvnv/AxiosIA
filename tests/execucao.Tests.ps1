# Testes de exemplo da execucao do Validador em repositorios sinteticos (Pester 5+).
# Rodar: Invoke-Pester ./tests/execucao.Tests.ps1
# Requisitos: 10.2, 10.9, 10.10, 10.11, 10.12
#
# Cada teste copia scripts/validar.ps1 para um repositorio sintetico em TestDrive e o executa em um
# processo pwsh separado (pwsh -NoProfile -File ... -Raiz <dir>). O termos-proibidos.txt e montado em
# tempo de execucao; nenhum termo proibido real aparece neste arquivo.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Gerador.ps1')

    $script:ValidadorOriginal = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts' 'validar.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:Utf8 = [System.Text.UTF8Encoding]::new($false)
    $script:Contador = 0
    # Termo sintetico montado por concatenacao (nunca literal).
    $script:Termo = Join-Partes 'q', 'z', 'x', 'proibido', 'teste'

    function Write-Arq {
        param([string]$Raiz, [string]$Rel, [string]$Texto)
        $c = Join-Path $Raiz $Rel
        New-Item -ItemType Directory -Force -Path (Split-Path $c -Parent) | Out-Null
        [System.IO.File]::WriteAllText($c, $Texto, $script:Utf8)
    }

    function New-ReadmeValido {
        @'
# Repositorio sintetico

Descricao simples.

## 1. Tema e objetivo

Estudar um tema de exemplo.

## 2. Fontes e por que são confiáveis

Veja o [registro](docs/fontes.md).

## 3. Diretriz de comportamento

Texto da diretriz.

## 4. Perguntas, respostas e fontes

Uma pergunta e sua resposta.

## 5. Link do notebook

https://notebook.example/abc123
'@
    }

    # Cria um repositorio sintetico valido e retorna o diretorio.
    function New-RepoSintetico {
        $script:Contador++
        $raiz = Join-Path $TestDrive "repo$($script:Contador)"
        New-Item -ItemType Directory -Force -Path (Join-Path $raiz 'scripts') | Out-Null
        Copy-Item -LiteralPath $script:ValidadorOriginal -Destination (Join-Path $raiz 'scripts' 'validar.ps1')
        Write-Arq $raiz 'scripts/termos-proibidos.txt' ($script:Termo + "`n")
        Write-Arq $raiz 'README.md' (New-ReadmeValido)
        Write-Arq $raiz 'docs/fontes.md' "Registro de fontes de exemplo.`n"
        return $raiz
    }

    # Executa o script copiado no repositorio; -SemRaiz omite o parametro.
    function Invoke-Validador {
        param([string]$Raiz, [switch]$SemRaiz)
        $script = Join-Path $Raiz 'scripts' 'validar.ps1'
        if ($SemRaiz) { $saida = & $script:Pwsh -NoProfile -File $script 2>&1 }
        else { $saida = & $script:Pwsh -NoProfile -File $script -Raiz $Raiz 2>&1 }
        $codigo = $LASTEXITCODE
        return [pscustomobject]@{ Linhas = @($saida | ForEach-Object { "$_" }); Codigo = $codigo }
    }
}

Describe 'Execucao do Validador: repositorio valido' {
    It 'termina com codigo 0 e uma linha OK por verificacao, sem FALHA' {
        $raiz = New-RepoSintetico
        $r = Invoke-Validador -Raiz $raiz
        $r.Codigo | Should -Be 0 -Because ($r.Linhas -join "`n")
        @($r.Linhas | Where-Object { $_ -match '^OK ' }).Count | Should -Be 6
        @($r.Linhas | Where-Object { $_ -match 'FALHA' }).Count | Should -Be 0
        $r.Linhas | Should -Not -Contain 'Detalhes das falhas:'
    }

    It 'roda sem parametros (Raiz opcional, padrao = pasta pai de scripts/)' {
        $raiz = New-RepoSintetico
        $r = Invoke-Validador -Raiz $raiz -SemRaiz
        $r.Codigo | Should -Be 0 -Because ($r.Linhas -join "`n")
        @($r.Linhas | Where-Object { $_ -match '^OK ' }).Count | Should -Be 6
    }
}

Describe 'Execucao do Validador: repositorio com falhas' {
    BeforeAll {
        $script:RaizFalha = New-RepoSintetico
        # Link quebrado, arquivo citado vazio, Placeholder e termo proibido em docs/.
        $readme = (New-ReadmeValido) + "`nVeja [sumido](docs/sumido.md) e [vazio](docs/vazio.md).`n[PREENCHER: algo]`n"
        Write-Arq $script:RaizFalha 'README.md' $readme
        Write-Arq $script:RaizFalha 'docs/vazio.md' ''
        Write-Arq $script:RaizFalha 'docs/sub/nota.md' ("Texto com $($script:Termo) no meio.`n")
        $script:RF = Invoke-Validador -Raiz $script:RaizFalha
        $script:TextoRF = $script:RF.Linhas -join "`n"
    }

    It 'termina com codigo 1' {
        $script:RF.Codigo | Should -Be 1 -Because $script:TextoRF
    }

    It 'imprime FALHA para as verificacoes afetadas e OK para as demais, sem parar na primeira' {
        $script:RF.Linhas | Where-Object { $_ -match '^FALHA .*Links relativos' } | Should -Not -BeNullOrEmpty
        $script:RF.Linhas | Where-Object { $_ -match '^FALHA .*Arquivos citados' } | Should -Not -BeNullOrEmpty
        $script:RF.Linhas | Where-Object { $_ -match '^FALHA .*Placeholder' } | Should -Not -BeNullOrEmpty
        $script:RF.Linhas | Where-Object { $_ -match '^FALHA .*termos proibidos' } | Should -Not -BeNullOrEmpty
        $script:RF.Linhas | Where-Object { $_ -match '^OK .*cinco se' } | Should -Not -BeNullOrEmpty
        # O Placeholder anexado ao fim do README cai na secao "Link do notebook" e tambem a invalida.
        $script:RF.Linhas | Where-Object { $_ -match '^FALHA .*Link do Notebook' } | Should -Not -BeNullOrEmpty
        @($script:RF.Linhas | Where-Object { $_ -match '^(OK|FALHA) ' }).Count | Should -Be 6
    }

    It 'lista os detalhes das falhas com caminhos relativos usando /' {
        $script:RF.Linhas | Should -Contain 'Detalhes das falhas:'
        $script:TextoRF | Should -Match '(?m)^\s+docs/sumido\.md\s*$'
        $script:TextoRF | Should -Match '(?m)^\s+docs/vazio\.md\s*$'
        $script:TextoRF | Should -Match '(?m)^\s+README\.md: \[PREENCHER: algo\]\s*$'
        $script:TextoRF | Should -Match ('(?m)^\s+docs/sub/nota\.md: ' + [regex]::Escape($script:Termo) + '\s*$')
    }

    It 'nao usa barra invertida nos caminhos dos detalhes' {
        $idx = [array]::IndexOf($script:RF.Linhas, 'Detalhes das falhas:')
        $idx | Should -BeGreaterOrEqual 0
        $detalhes = $script:RF.Linhas[$idx..($script:RF.Linhas.Count - 1)]
        @($detalhes | Where-Object { $_ -match '\\' }).Count | Should -Be 0
    }
}

Describe 'Execucao do Validador: README ausente ou vazio' {
    It 'README ausente: FALHA nas verificacoes 1, 2, 3 e 5 com a causa, 4 e 6 seguem, codigo 1' {
        $raiz = New-RepoSintetico
        Remove-Item -LiteralPath (Join-Path $raiz 'README.md')
        $r = Invoke-Validador -Raiz $raiz
        $r.Codigo | Should -Be 1
        @($r.Linhas | Where-Object { $_ -match '^FALHA ' }).Count | Should -Be 4
        @($r.Linhas | Where-Object { $_ -match '^OK ' }).Count | Should -Be 2
        @($r.Linhas | Where-Object { $_ -match 'README\.md ausente ou vazio' }).Count | Should -Be 4
    }

    It 'README vazio: mesmo comportamento' {
        $raiz = New-RepoSintetico
        Write-Arq $raiz 'README.md' ''
        $r = Invoke-Validador -Raiz $raiz
        $r.Codigo | Should -Be 1
        @($r.Linhas | Where-Object { $_ -match '^FALHA ' }).Count | Should -Be 4
        @($r.Linhas | Where-Object { $_ -match 'README\.md ausente ou vazio' }).Count | Should -Be 4
    }

    It 'README so com espacos conta como vazio' {
        $raiz = New-RepoSintetico
        Write-Arq $raiz 'README.md' "   `n`n  "
        $r = Invoke-Validador -Raiz $raiz
        $r.Codigo | Should -Be 1
        @($r.Linhas | Where-Object { $_ -match 'README\.md ausente ou vazio' }).Count | Should -Be 4
    }
}

Describe 'Execucao do Validador: termos-proibidos.txt ausente ou vazio' {
    It 'ausente: so a verificacao 6 falha, com a causa, e o codigo e 1' {
        $raiz = New-RepoSintetico
        Remove-Item -LiteralPath (Join-Path $raiz 'scripts' 'termos-proibidos.txt')
        $r = Invoke-Validador -Raiz $raiz
        $r.Codigo | Should -Be 1
        @($r.Linhas | Where-Object { $_ -match '^FALHA ' }).Count | Should -Be 1
        @($r.Linhas | Where-Object { $_ -match '^OK ' }).Count | Should -Be 5
        $r.Linhas | Where-Object { $_ -match 'termos-proibidos\.txt ausente ou vazio' } | Should -Not -BeNullOrEmpty
    }

    It 'vazio: so a verificacao 6 falha, com a causa, e o codigo e 1' {
        $raiz = New-RepoSintetico
        Write-Arq $raiz 'scripts/termos-proibidos.txt' ''
        $r = Invoke-Validador -Raiz $raiz
        $r.Codigo | Should -Be 1
        @($r.Linhas | Where-Object { $_ -match '^FALHA ' }).Count | Should -Be 1
        $r.Linhas | Where-Object { $_ -match 'termos-proibidos\.txt ausente ou vazio' } | Should -Not -BeNullOrEmpty
    }

    It 'so com linhas em branco: tratado como vazio' {
        $raiz = New-RepoSintetico
        Write-Arq $raiz 'scripts/termos-proibidos.txt' "`n  `n"
        $r = Invoke-Validador -Raiz $raiz
        $r.Codigo | Should -Be 1
        $r.Linhas | Where-Object { $_ -match 'termos-proibidos\.txt ausente ou vazio' } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Execucao do Validador: somente leitura e sem rede' {
    It 'nao altera nenhum arquivo do repositorio (hashes iguais antes e depois, valido)' {
        $raiz = New-RepoSintetico
        $antes = Get-HashArvore -Raiz $raiz
        [void](Invoke-Validador -Raiz $raiz)
        $depois = Get-HashArvore -Raiz $raiz
        $depois | Should -Be $antes
    }

    It 'nao altera nenhum arquivo do repositorio (hashes iguais antes e depois, com falhas)' {
        $raiz = New-RepoSintetico
        Write-Arq $raiz 'README.md' ((New-ReadmeValido) + "`n[x](docs/nao-existe.md) TODO`n")
        Write-Arq $raiz 'docs/sub/nota.md' ("$($script:Termo)`n")
        $antes = Get-HashArvore -Raiz $raiz
        $r = Invoke-Validador -Raiz $raiz
        $r.Codigo | Should -Be 1
        (Get-HashArvore -Raiz $raiz) | Should -Be $antes
    }

    It 'nao cria nem remove arquivos (lista de caminhos igual)' {
        $raiz = New-RepoSintetico
        $lista = { @(Get-ChildItem -LiteralPath $raiz -Recurse -Force | ForEach-Object FullName | Sort-Object) }
        $antes = & $lista
        [void](Invoke-Validador -Raiz $raiz)
        (& $lista) | Should -Be $antes
    }

    It 'o script nao contem comandos de rede nem de git' {
        $texto = Get-Content -LiteralPath $script:ValidadorOriginal -Raw -Encoding UTF8
        $texto | Should -Not -Match '(?i)Invoke-WebRequest|Invoke-RestMethod|System\.Net|WebClient|HttpClient|\bcurl\b|\bwget\b|Test-NetConnection'
        $texto | Should -Not -Match '(?im)^\s*(git|gh)\s+\w+'
        $texto | Should -Not -Match '(?i)Start-Process|\bgit\s+(push|pull|fetch|clone|remote)'
    }
}
