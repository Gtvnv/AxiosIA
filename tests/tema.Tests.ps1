# Testes de propriedade da troca de Tema e da escrita atômica (Pester 5+).
# Feature: axios-segundo-cerebro
# Rodar: Invoke-Pester ./tests/tema.Tests.ps1
# Para reproduzir uma falha: $env:AXIOS_SEED = <semente impressa no inicio do teste>.
# Cada Describe cobre uma propriedade; os Describes de atomicidade e Evoluções entram depois.

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'scripts' 'validar.ps1')
    . (Join-Path $PSScriptRoot '..' 'scripts' 'tema.ps1')
    . (Join-Path $PSScriptRoot 'Gerador.ps1')
    $script:Iteracoes = 100

    function script:New-TemaSintetico {
        # Frase alfanumerica (sem ponto), opcionalmente com acento, com prefixo para evitar colisoes.
        param([string]$Prefixo)
        $t = $Prefixo + (New-Frase -MinPalavras 1 -MaxPalavras 8)
        if (New-Booleano) { $t += [char]::ConvertFromUtf32(0x00E7) + [char]::ConvertFromUtf32(0x00E3) + 'o' }
        return $t
    }

    function script:New-ParTemas {
        # Par (antigo, novo) em que nenhum contem o outro.
        do {
            $a = New-TemaSintetico -Prefixo 'ant'
            $n = New-TemaSintetico -Prefixo 'nov'
        } while ($n.Contains($a) -or $a.Contains($n))
        return [pscustomobject]@{ Antigo = $a; Novo = $n }
    }

    function script:Write-ArquivoUtf8 {
        param([string]$Caminho, [string]$Texto)
        New-Item -ItemType Directory -Force -Path (Split-Path $Caminho -Parent) | Out-Null
        [System.IO.File]::WriteAllText($Caminho, $Texto, [System.Text.UTF8Encoding]::new($false))
    }

    function script:Read-ArquivoUtf8 {
        param([string]$Caminho)
        return [System.IO.File]::ReadAllText($Caminho, [System.Text.UTF8Encoding]::new($false))
    }

    function script:New-CorpoComTema {
        # Corpo com 0..4 ocorrencias do Tema em posicoes variadas, mais ruido (incluindo o Tema em
        # maiusculas, que NAO deve ser substituido). Retorna o texto e o numero de ocorrencias.
        param([string]$Tema, [switch]$ComMarcador)
        $pedacos = @()
        $n = New-Inteiro -Min 0 -Max 4
        $total = New-Inteiro -Min 1 -Max 8
        $posicoes = @(1..$n | ForEach-Object { New-Inteiro -Min 0 -Max $total })
        for ($i = 0; $i -le $total; $i++) {
            foreach ($p in $posicoes) {
                if ($p -eq $i) {
                    $pedacos += $Tema
                    if ($ComMarcador -and (New-Booleano)) { $pedacos[-1] += ' (proposto)' }
                }
            }
            $pedacos += (New-Frase -MinPalavras 0 -MaxPalavras 6)
            if ((New-Inteiro 0 3) -eq 0) { $pedacos += $Tema.ToUpperInvariant() }
        }
        return [pscustomobject]@{ Texto = ($pedacos -join ' | '); Ocorrencias = $n }
    }

    function script:New-RepoSintetico {
        # Repositorio sintetico: README.md, docs/diretriz-de-comportamento.md e 0..4 outros docs/*.md.
        param([string]$Raiz, [string]$Antigo, [string]$Objetivo, [switch]$ComMarcador)
        $marcador = if ($ComMarcador) { ' (proposto)' } else { '' }
        $c = New-CorpoComTema -Tema $Antigo -ComMarcador:$ComMarcador
        $readme = "# AXIOS`n`n## Tema e objetivo`n`nTema: $Antigo, com o objetivo de $Objetivo$marcador.`n`n" + $c.Texto + "`n"
        Write-ArquivoUtf8 (Join-Path $Raiz 'README.md') $readme

        $c = New-CorpoComTema -Tema $Antigo -ComMarcador:$ComMarcador
        $diretriz = "Comporte-se como um especialista em $Antigo. Responda em português do Brasil.`n" + $c.Texto + "`n"
        Write-ArquivoUtf8 (Join-Path $Raiz 'docs/diretriz-de-comportamento.md') $diretriz

        $extras = New-Inteiro -Min 0 -Max 4
        for ($k = 0; $k -lt $extras; $k++) {
            $c = New-CorpoComTema -Tema $Antigo -ComMarcador:$ComMarcador
            Write-ArquivoUtf8 (Join-Path $Raiz "docs/extra$k.md") ("# Extra $k`n`n" + $c.Texto + "`n")
        }
    }

    function script:Get-ArquivosMd {
        param([string]$Raiz)
        return @(Get-ChildItem -LiteralPath $Raiz -Recurse -File -Filter '*.md' | Sort-Object FullName)
    }

    function script:Get-Residuos {
        param([string]$Raiz)
        return @(Get-ChildItem -LiteralPath $Raiz -Recurse -File -Force |
                Where-Object { $_.Name -match '\.axios-(novo|bak)$' })
    }
}

Describe 'Property 5: Troca de Tema' {
    # Feature: axios-segundo-cerebro, Property 5: Troca de Tema
    # (design.md: Property 13 "A troca de Tema atualiza todos os arquivos")
    # **Validates: Requirements 1.3, 1.4, 1.5, 1.6**

    It 'ConvertTo-ConteudoNovo é pura, substitui todas as ocorrências literais (com diferenciação de maiúsculas) e preserva o resto (>= 100 iterações)' {
        [void](Initialize-Gerador -Contexto 'Property 5 (ConvertTo-ConteudoNovo)')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $par = New-ParTemas
            $semente = Get-SementeAtual
            $ctx = "iteração $i, semente base $semente, antigo='$($par.Antigo)', novo='$($par.Novo)'"

            # Sequencia de tokens: Tema antigo (T), Tema em maiusculas (U, nao substituido),
            # marcador (M) e ruido (R). Separados por " | " para nao formar ocorrencias na juncao.
            $n = New-Inteiro -Min 0 -Max 12
            $entrada = @(); $esperado = @(); $esperadoConfirmado = @()
            $ocorrencias = 0
            for ($k = 0; $k -lt $n; $k++) {
                switch (Select-Aleatorio @('T', 'T', 'U', 'M', 'R', 'R')) {
                    'T' { $entrada += $par.Antigo; $esperado += $par.Novo; $esperadoConfirmado += $par.Novo; $ocorrencias++ }
                    'U' { $u = $par.Antigo.ToUpperInvariant(); $entrada += $u; $esperado += $u; $esperadoConfirmado += $u }
                    'M' {
                        # Marcador colado ao token anterior (com espacos/tabs antes dele).
                        $antes = Select-Aleatorio @(' ', '  ', "`t", '')
                        if ($entrada.Count -gt 0) {
                            $entrada[-1] += "$antes(proposto)"; $esperado[-1] += "$antes(proposto)"
                        }
                    }
                    'R' { $r = New-Frase -MinPalavras 0 -MaxPalavras 5; $entrada += $r; $esperado += $r; $esperadoConfirmado += $r }
                }
            }
            $texto = $entrada -join ' | '
            $copia = [string]::new($texto.ToCharArray())

            $sem = ConvertTo-ConteudoNovo -Texto $texto -TemaAntigo $par.Antigo -TemaNovo $par.Novo
            $com = ConvertTo-ConteudoNovo -Texto $texto -TemaAntigo $par.Antigo -TemaNovo $par.Novo -Confirmar

            # Pureza: mesma entrada, mesma saida; entrada nao muda.
            $texto | Should -BeExactly $copia -Because $ctx
            (ConvertTo-ConteudoNovo -Texto $texto -TemaAntigo $par.Antigo -TemaNovo $par.Novo) | Should -BeExactly $sem -Because $ctx

            # Sem -Confirmar: so troca o Tema, marcador permanece.
            $sem | Should -BeExactly ($esperado -join ' | ') -Because $ctx
            $sem.Contains($par.Antigo) | Should -BeFalse -Because $ctx
            ([regex]::Matches($sem, [regex]::Escape($par.Novo)).Count) | Should -BeGreaterOrEqual $ocorrencias -Because $ctx

            # Com -Confirmar: nenhum "(proposto)" resta.
            $com | Should -Not -Match '\(proposto\)' -Because $ctx
            $com.Contains($par.Antigo) | Should -BeFalse -Because $ctx
            ($com -replace '[ \t]*\(proposto\)', '') | Should -BeExactly $com -Because $ctx
            $semMarcador = [regex]::Replace($sem, '[ \t]*\(proposto\)', '')
            $com | Should -BeExactly $semMarcador -Because $ctx
        }
    }

    It 'Set-Tema grava todos os arquivos com o novo Tema, sem o antigo, preservando o Objetivo e o restante (>= 100 iterações)' {
        [void](Initialize-Gerador -Contexto 'Property 5 (Set-Tema sucesso)')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $raiz = Join-Path $TestDrive "p5-ok-$i"
            $par = New-ParTemas
            $objetivo = 'obj ' + (New-Frase -MinPalavras 1 -MaxPalavras 6)
            $semente = Get-SementeAtual
            $ctx = "iteração $i, semente base $semente, antigo='$($par.Antigo)', novo='$($par.Novo)'"
            New-RepoSintetico -Raiz $raiz -Antigo $par.Antigo -Objetivo $objetivo

            $antes = @{}
            foreach ($f in Get-ArquivosMd $raiz) { $antes[$f.FullName] = Read-ArquivoUtf8 $f.FullName }

            # O Tema pode vir com espacos nas pontas.
            $entrada = (Select-Aleatorio @('', ' ', '  ')) + $par.Novo + '.' + (Select-Aleatorio @('', ' '))
            $r = Set-Tema -Raiz $raiz -Tema $entrada

            $r.Sucesso | Should -BeTrue -Because "$ctx; motivo: $($r.Motivo)"
            @(Get-Residuos $raiz).Count | Should -Be 0 -Because $ctx

            foreach ($f in Get-ArquivosMd $raiz) {
                $depois = Read-ArquivoUtf8 $f.FullName
                $depois.Contains($par.Antigo) | Should -BeFalse -Because "$ctx; $($f.Name)"
                # Restante preservado: equivale a substituicao literal ordinal sobre o original.
                $depois | Should -BeExactly $antes[$f.FullName].Replace($par.Antigo, $par.Novo) -Because "$ctx; $($f.Name)"
                if ($antes[$f.FullName].Contains($par.Antigo)) {
                    $depois.Contains($par.Novo) | Should -BeTrue -Because "$ctx; $($f.Name)"
                }
            }
            # Objetivo preservado no README.
            (Read-ArquivoUtf8 (Join-Path $raiz 'README.md')).Contains("com o objetivo de $objetivo.") | Should -BeTrue -Because $ctx
            # A diretriz passa a citar o Tema novo na primeira frase.
            (Read-ArquivoUtf8 (Join-Path $raiz 'docs/diretriz-de-comportamento.md')).StartsWith("Comporte-se como um especialista em $($par.Novo).") | Should -BeTrue -Because $ctx
        }
    }

    It 'Set-Tema -Confirmar remove "(proposto)" de todos os arquivos e mantém o Tema (>= 100 iterações)' {
        [void](Initialize-Gerador -Contexto 'Property 5 (Set-Tema -Confirmar)')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $raiz = Join-Path $TestDrive "p5-conf-$i"
            $par = New-ParTemas
            $objetivo = 'obj ' + (New-Frase -MinPalavras 1 -MaxPalavras 6)
            $semente = Get-SementeAtual
            $ctx = "iteração $i, semente base $semente, tema='$($par.Antigo)'"
            New-RepoSintetico -Raiz $raiz -Antigo $par.Antigo -Objetivo $objetivo -ComMarcador

            $antes = @{}
            foreach ($f in Get-ArquivosMd $raiz) { $antes[$f.FullName] = Read-ArquivoUtf8 $f.FullName }

            $r = Set-Tema -Raiz $raiz -Confirmar

            $r.Sucesso | Should -BeTrue -Because "$ctx; motivo: $($r.Motivo)"
            @(Get-Residuos $raiz).Count | Should -Be 0 -Because $ctx
            foreach ($f in Get-ArquivosMd $raiz) {
                $depois = Read-ArquivoUtf8 $f.FullName
                $depois | Should -Not -Match '\(proposto\)' -Because "$ctx; $($f.Name)"
                $depois | Should -BeExactly ([regex]::Replace($antes[$f.FullName], '[ \t]*\(proposto\)', '')) -Because "$ctx; $($f.Name)"
            }
        }
    }

    It 'Set-Tema não grava nada com Tema inválido (vazio, > 300 caracteres, sem ponto final) (>= 100 iterações)' {
        [void](Initialize-Gerador -Contexto 'Property 5 (Set-Tema inválido)')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $raiz = Join-Path $TestDrive "p5-inv-$i"
            $par = New-ParTemas
            $semente = Get-SementeAtual
            New-RepoSintetico -Raiz $raiz -Antigo $par.Antigo -Objetivo 'obj teste'
            $antes = Get-HashArvore -Raiz $raiz

            $tipo = Select-Aleatorio @('vazio', 'espacos', 'longo', 'sem-ponto', 'ponto-duplo')
            $invalido = switch ($tipo) {
                'vazio' { '' }
                'espacos' { ' ' * (New-Inteiro -Min 1 -Max 5) }
                'longo' {
                    $t = ''
                    while ($t.Length -le 300) { $t += (New-Palavra) + ' ' }
                    $t.Trim() + '.'
                }
                'sem-ponto' { $par.Novo }
                'ponto-duplo' { $par.Novo + '..' }
            }
            $ctx = "iteração $i, semente base $semente, tipo=$tipo"

            $r = Set-Tema -Raiz $raiz -Tema $invalido

            $r.Sucesso | Should -BeFalse -Because $ctx
            $r.Motivo | Should -Not -BeNullOrEmpty -Because $ctx
            @(Get-Residuos $raiz).Count | Should -Be 0 -Because $ctx
            ((Get-HashArvore -Raiz $raiz) -join "`n") | Should -BeExactly ($antes -join "`n") -Because $ctx
        }
    }
}

Describe 'Property 14: Atomicidade da troca de Tema' {
    # Feature: axios-segundo-cerebro, Property 14: Atomicidade da troca de Tema
    # (design.md: "para qualquer arquivo escolhido para falhar na fase 1 ou 2, o estado final de todos
    # os arquivos e identico ao inicial, sem .axios-novo/.axios-bak, e o resultado identifica o
    # arquivo causador"). Temas rejeitados por Test-FraseTema sao cobertos no Describe da Property 5.
    # **Validates: Requirements 1.6, 1.7**

    BeforeAll {
        function script:Get-Instantaneo {
            # Mapa caminho relativo -> hash SHA256 de todos os arquivos sob a raiz (inclui residuos).
            param([string]$Raiz)
            $base = (Resolve-Path -LiteralPath $Raiz).Path
            $mapa = [ordered]@{}
            foreach ($f in (Get-ChildItem -LiteralPath $base -Recurse -File -Force | Sort-Object FullName)) {
                $rel = $f.FullName.Substring($base.Length)
                $mapa[$rel] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
            }
            return $mapa
        }

        function script:ConvertTo-TextoInstantaneo {
            param($Mapa)
            return (($Mapa.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n")
        }
    }

    It 'Set-ArquivosAtomico com falha injetada em arquivo e fase aleatórios restaura o estado original; sem falha, todos mudam (>= 100 iterações)' {
        [void](Initialize-Gerador -Contexto 'Property 14 (Set-ArquivosAtomico)')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $raiz = Join-Path $TestDrive "p14-a-$i"
            New-Item -ItemType Directory -Force -Path $raiz | Out-Null
            $semente = Get-SementeAtual

            $n = New-Inteiro -Min 1 -Max 6
            $itens = @()
            for ($k = 0; $k -lt $n; $k++) {
                $caminho = Join-Path $raiz "arq$k.md"
                # Cerca de 1/3 dos arquivos nao existia antes.
                $existe = (New-Inteiro -Min 0 -Max 2) -ne 0
                if ($existe) { Write-ArquivoUtf8 $caminho ("original $k " + (New-Frase -MinPalavras 0 -MaxPalavras 6)) }
                $itens += [pscustomobject]@{ Caminho = $caminho; Conteudo = ("novo $k " + (New-Frase -MinPalavras 1 -MaxPalavras 6)) }
            }
            $antes = Get-Instantaneo $raiz

            $falhar = (New-Inteiro -Min 0 -Max 3) -ne 0   # ~75% com falha, ~25% sem
            $alvo = (Select-Aleatorio $itens).Caminho
            $fase = New-Inteiro -Min 1 -Max 2
            $modo = Select-Aleatorio @('throw', 'true')
            $ctx = "iteração $i, semente base $semente, n=$n, falhar=$falhar, fase=$fase, modo=$modo, alvo=$(Split-Path $alvo -Leaf)"

            if ($falhar) {
                $bloco = {
                    param($f, $c)
                    if ($f -eq $fase -and $c -eq $alvo) {
                        if ($modo -eq 'throw') { throw 'falha injetada' } else { return $true }
                    }
                }.GetNewClosure()
                $r = Set-ArquivosAtomico -Itens $itens -FalhaInjetada $bloco

                $r.Sucesso | Should -BeFalse -Because $ctx
                $r.ArquivoCausador | Should -BeExactly $alvo -Because $ctx
                $r.Fase | Should -Be $fase -Because $ctx
                $r.FalhaNaReversao | Should -BeFalse -Because $ctx
                @(Get-Residuos $raiz).Count | Should -Be 0 -Because $ctx
                (ConvertTo-TextoInstantaneo (Get-Instantaneo $raiz)) | Should -BeExactly (ConvertTo-TextoInstantaneo $antes) -Because $ctx
            }
            else {
                $r = Set-ArquivosAtomico -Itens $itens
                $r.Sucesso | Should -BeTrue -Because "$ctx; $($r.Mensagem)"
                @(Get-Residuos $raiz).Count | Should -Be 0 -Because $ctx
                foreach ($it in $itens) {
                    Read-ArquivoUtf8 $it.Caminho | Should -BeExactly $it.Conteudo -Because $ctx
                }
            }
        }
    }

    It 'Set-Tema com falha injetada em arquivo e fase aleatórios deixa todos os arquivos idênticos ao original; sem falha, todos mudam (>= 100 iterações)' {
        [void](Initialize-Gerador -Contexto 'Property 14 (Set-Tema)')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $raiz = Join-Path $TestDrive "p14-t-$i"
            $par = New-ParTemas
            $semente = Get-SementeAtual
            New-RepoSintetico -Raiz $raiz -Antigo $par.Antigo -Objetivo 'obj teste'
            $antes = Get-Instantaneo $raiz

            # Arquivos que Set-Tema vai alterar: os que citam o Tema antigo.
            $afetados = @(Get-ArquivosMd $raiz | Where-Object { (Read-ArquivoUtf8 $_.FullName).Contains($par.Antigo) } | ForEach-Object { $_.FullName })
            $afetados.Count | Should -BeGreaterOrEqual 2 -Because "semente $semente"

            $falhar = (New-Inteiro -Min 0 -Max 3) -ne 0
            $alvo = Select-Aleatorio $afetados
            $fase = New-Inteiro -Min 1 -Max 2
            $modo = Select-Aleatorio @('throw', 'true')
            $ctx = "iteração $i, semente base $semente, falhar=$falhar, fase=$fase, modo=$modo, alvo=$(Split-Path $alvo -Leaf)"
            $entrada = $par.Novo + '.'

            if ($falhar) {
                $bloco = {
                    param($f, $c)
                    if ($f -eq $fase -and ([System.IO.Path]::GetFullPath($c) -eq [System.IO.Path]::GetFullPath($alvo))) {
                        if ($modo -eq 'throw') { throw 'falha injetada' } else { return $true }
                    }
                }.GetNewClosure()
                $r = Set-Tema -Raiz $raiz -Tema $entrada -FalhaInjetada $bloco

                $r.Sucesso | Should -BeFalse -Because $ctx
                $r.Motivo | Should -Not -BeNullOrEmpty -Because $ctx
                [System.IO.Path]::GetFullPath($r.ArquivoCausador) | Should -BeExactly ([System.IO.Path]::GetFullPath($alvo)) -Because $ctx
                @($r.ArquivosAlterados).Count | Should -Be 0 -Because $ctx
                @(Get-Residuos $raiz).Count | Should -Be 0 -Because $ctx
                (ConvertTo-TextoInstantaneo (Get-Instantaneo $raiz)) | Should -BeExactly (ConvertTo-TextoInstantaneo $antes) -Because $ctx
            }
            else {
                $r = Set-Tema -Raiz $raiz -Tema $entrada
                $r.Sucesso | Should -BeTrue -Because "$ctx; $($r.Motivo)"
                @(Get-Residuos $raiz).Count | Should -Be 0 -Because $ctx
                $depois = Get-Instantaneo $raiz
                foreach ($f in $afetados) {
                    $rel = $f.Substring((Resolve-Path -LiteralPath $raiz).Path.Length)
                    $depois[$rel] | Should -Not -BeExactly $antes[$rel] -Because "$ctx; $rel"
                    (Read-ArquivoUtf8 $f).Contains($par.Antigo) | Should -BeFalse -Because "$ctx; $rel"
                }
            }
        }
    }
}

Describe 'Property 20: Solicitação de Evoluções inválida é rejeitada por inteiro' {
    # Feature: axios-segundo-cerebro, Property 20: Solicitação de Evoluções com item inexistente é rejeitada por inteiro
    # (cobre também pedidos com 0 itens e com mais de 4 itens, conforme Requirement 12.4)
    # **Validates: Requirements 12.4**

    BeforeAll {
        $script:EvolucoesReal = [System.IO.File]::ReadAllText(
            (Join-Path $PSScriptRoot '..' 'docs' 'evolucoes.md'), [System.Text.UTF8Encoding]::new($false))

        function script:Remove-Acentos {
            param([string]$Texto)
            $d = $Texto.Normalize([System.Text.NormalizationForm]::FormD)
            $sb = [System.Text.StringBuilder]::new()
            foreach ($c in $d.ToCharArray()) {
                if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
            }
            return $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)
        }

        function script:New-NomeDesconhecido {
            # Nome que nao e igual (ordinal, com caixa) a nenhum titulo valido.
            param([string[]]$Validos)
            while ($true) {
                $base = Select-Aleatorio $Validos
                $tipo = Select-Aleatorio @('aleatorio', 'caixa', 'acentos', 'quase-igual', 'vazio')
                $nome = switch ($tipo) {
                    'aleatorio' { New-StringAleatoria -MinComprimento 1 -MaxComprimento 40 -Alfabeto Misto }
                    'caixa' { Set-CaixaAleatoria $base }
                    'acentos' { Remove-Acentos $base }
                    'vazio' { if (New-Booleano) { '' } else { ' ' * (New-Inteiro -Min 1 -Max 3) } }
                    'quase-igual' {
                        switch (New-Inteiro -Min 0 -Max 4) {
                            0 { $base + ' ' }
                            1 { ' ' + $base }
                            2 { $base + '.' }
                            3 { $base.Substring(0, $base.Length - 1) }
                            4 { $p = New-Inteiro -Min 0 -Max ($base.Length - 1); $base.Remove($p, 1).Insert($p, 'x') }
                        }
                    }
                }
                if (-not ($Validos -ccontains $nome)) { return $nome }
            }
        }
    }

    It 'rejeita pedidos com 0 itens, mais de 4 itens ou nome desconhecido, informa o motivo e não altera nada (>= 100 iterações)' {
        [void](Initialize-Gerador -Contexto 'Property 20 (Add-Evolucoes rejeição)')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $raiz = Join-Path $TestDrive "p20-$i"
            $semente = Get-SementeAtual

            # Repositorio sintetico: README (com ou sem secao Evolucoes), evolucoes.md real e roteiro.
            $extra = if (New-Booleano) { "`n## Evoluções`n`n- **Quiz e glossário**: ja listado.`n" } else { '' }
            Write-ArquivoUtf8 (Join-Path $raiz 'README.md') ("# AXIOS`n`n## Tema e objetivo`n`n" + (New-Frase -MinPalavras 0 -MaxPalavras 10) + "`n$extra")
            Write-ArquivoUtf8 (Join-Path $raiz 'docs/evolucoes.md') $script:EvolucoesReal
            Write-ArquivoUtf8 (Join-Path $raiz 'docs/roteiro-manual.md') ("# Roteiro`n`n" + (New-Frase -MinPalavras 0 -MaxPalavras 10) + "`n")

            $validos = @(Get-EvolucoesDisponiveis -Raiz $raiz | ForEach-Object { $_.Titulo })
            $validos.Count | Should -Be 4 -Because "semente $semente"

            $tipo = Select-Aleatorio @('zero', 'zero-nulo', 'muitos', 'desconhecido', 'misto')
            $desconhecidos = @()
            switch ($tipo) {
                'zero' { $pedido = @() }
                'zero-nulo' { $pedido = $null }
                'muitos' {
                    # 5 a 8 itens, validos (com repeticao) ou nao.
                    $pedido = @(1..(New-Inteiro -Min 5 -Max 8) | ForEach-Object {
                            if (New-Booleano) { Select-Aleatorio $validos } else { New-NomeDesconhecido -Validos $validos }
                        })
                }
                'desconhecido' {
                    $desconhecidos = @(1..(New-Inteiro -Min 1 -Max 4) | ForEach-Object { New-NomeDesconhecido -Validos $validos })
                    $pedido = $desconhecidos
                }
                'misto' {
                    $nd = New-Inteiro -Min 1 -Max 3
                    $desconhecidos = @(1..$nd | ForEach-Object { New-NomeDesconhecido -Validos $validos })
                    $nv = New-Inteiro -Min 0 -Max (4 - $nd)
                    $pedido = @($desconhecidos) + @(1..$nv | Where-Object { $_ } | ForEach-Object { Select-Aleatorio $validos })
                    $pedido = @($pedido | Sort-Object { (Get-Rng).Next() })
                }
            }
            $ctx = "iteração $i, semente base $semente, tipo=$tipo, pedido=[$((@($pedido) | ForEach-Object { "'$_'" }) -join ', ')]"

            $antes = Get-HashArvore -Raiz $raiz
            $r = Add-Evolucoes -Raiz $raiz -Nomes $pedido

            $r.Sucesso | Should -BeFalse -Because $ctx
            $r.Motivo | Should -Not -BeNullOrEmpty -Because $ctx
            @($r.Adicionadas).Count | Should -Be 0 -Because $ctx
            # O motivo lista as quatro opcoes validas e, quando ha, os nomes inexistentes.
            foreach ($v in $validos) { $r.Motivo.Contains($v) | Should -BeTrue -Because "$ctx; opção '$v' ausente do motivo" }
            if ($tipo -in @('desconhecido', 'misto')) {
                foreach ($d in $desconhecidos) { $r.Motivo.Contains($d) | Should -BeTrue -Because "$ctx; nome '$d' ausente do motivo" }
            }
            # Nada alterado: mesmos caminhos, tamanhos e hashes; sem residuos.
            @(Get-Residuos $raiz).Count | Should -Be 0 -Because $ctx
            ((Get-HashArvore -Raiz $raiz) -join "`n") | Should -BeExactly ($antes -join "`n") -Because $ctx
        }
    }
}

Describe 'Property 20 (string vazia): elemento vazio em -Nomes é rejeitado com Motivo' {
    # **Validates: Requirements 12.4**
    It 'rejeita @("") e @("", "Quiz e glossário") com Motivo, sem ParameterBindingValidationException e sem gravar nada' {
        $raiz = Join-Path $TestDrive 'p20-vazio'
        Write-ArquivoUtf8 (Join-Path $raiz 'README.md') "# AXIOS`n`n## Tema e objetivo`n`ntexto`n"
        Write-ArquivoUtf8 (Join-Path $raiz 'docs/evolucoes.md') ([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..' 'docs' 'evolucoes.md'), [System.Text.UTF8Encoding]::new($false)))
        Write-ArquivoUtf8 (Join-Path $raiz 'docs/roteiro-manual.md') "# Roteiro`n`n1. **Passo.**`n"
        $antes = (Get-HashArvore -Raiz $raiz) -join "`n"

        foreach ($pedido in @(@(''), @('', 'Quiz e glossário'))) {
            $r = { Add-Evolucoes -Raiz $raiz -Nomes $pedido }.Invoke()[0]
            $r.Sucesso | Should -BeFalse
            $r.Motivo | Should -Not -BeNullOrEmpty
            $r.Motivo.Contains('Quiz e glossário') | Should -BeTrue -Because 'as quatro opções válidas são listadas'
            ((Get-HashArvore -Raiz $raiz) -join "`n") | Should -BeExactly $antes
            @(Get-Residuos $raiz).Count | Should -Be 0
        }
    }
}

Describe 'Property 21: Adição de Evoluções é idempotente e preserva o conteúdo' {
    # Feature: axios-segundo-cerebro, Property 21: Adição de Evoluções é idempotente e preserva o conteúdo
    # **Validates: Requirements 12.2, 12.3**

    BeforeAll {
        $script:EvolucoesReal21 = [System.IO.File]::ReadAllText(
            (Join-Path $PSScriptRoot '..' 'docs' 'evolucoes.md'), [System.Text.UTF8Encoding]::new($false))

        function script:Get-SubsecaoRoteiro {
            # Linhas da subsecao "## Titulo" no roteiro (ate o proximo "## " ou fim).
            param([string]$Texto, [string]$Titulo)
            $linhas = @($Texto -split "\r?\n")
            $ini = @(0..($linhas.Count - 1) | Where-Object { $linhas[$_] -ceq "## $Titulo" })
            if ($ini.Count -ne 1) { return $null }
            $corpo = @()
            for ($j = $ini[0] + 1; $j -lt $linhas.Count -and $linhas[$j] -notmatch '^## '; $j++) { $corpo += $linhas[$j] }
            return , $corpo
        }

        function script:Assert-EstadoEvolucoes {
            param([string]$Raiz, [string[]]$Titulos, $Disponiveis, [string]$RoteiroOriginal, [string]$ReadmeOriginal, [string[]]$Pre, [string]$Ctx)
            $readme = Read-ArquivoUtf8 (Join-Path $Raiz 'README.md')
            $roteiro = Read-ArquivoUtf8 (Join-Path $Raiz 'docs/roteiro-manual.md')

            # Seções obrigatórias intactas e na ordem.
            @(Find-SecoesFaltantes -TextoReadme $readme).Count | Should -Be 0 -Because $Ctx
            # Conteúdo anterior preservado.
            $readme.StartsWith($ReadmeOriginal.TrimEnd("`r", "`n")) | Should -BeTrue -Because $Ctx
            $roteiro.StartsWith($RoteiroOriginal.TrimEnd("`r", "`n")) | Should -BeTrue -Because $Ctx
            # Sem Placeholders novos e sem residuos.
            @(Find-Placeholders -Texto $readme).Count | Should -Be @(Find-Placeholders -Texto $ReadmeOriginal).Count -Because $Ctx
            @(Find-Placeholders -Texto $roteiro).Count | Should -Be @(Find-Placeholders -Texto $RoteiroOriginal).Count -Because $Ctx
            @(Get-Residuos $Raiz).Count | Should -Be 0 -Because $Ctx

            foreach ($t in $Titulos) {
                $d = $Disponiveis | Where-Object { $_.Titulo -ceq $t }
                # README: exatamente uma linha, descricao de 1 a 3 frases.
                ([regex]::Matches($readme, [regex]::Escape("**$t**")).Count) | Should -Be 1 -Because "$Ctx; README '$t'"
                $linha = @($readme -split "\r?\n" | Where-Object { $_.StartsWith("- **$t**: ") })
                $linha.Count | Should -Be 1 -Because "$Ctx; README '$t'"
                $frases = @($linha[0].Substring("- **$t**: ".Length) -split '(?<=[.!?])\s+' | Where-Object { $_.Trim().Length -gt 0 })
                $frases.Count | Should -BeIn @(1, 2, 3) -Because "$Ctx; frases '$t'"
                # Roteiro: uma subsecao com 10 passos numerados de 1 a 10.
                $sub = Get-SubsecaoRoteiro -Texto $roteiro -Titulo $t
                $sub | Should -Not -BeNullOrEmpty -Because "$Ctx; subseção '$t'"
                $nums = @($sub | Where-Object { $_ -match '^\d+\.\s' } | ForEach-Object { [int]($_ -replace '^(\d+)\..*$', '$1') })
                ($nums -join ',') | Should -BeExactly '1,2,3,4,5,6,7,8,9,10' -Because "$Ctx; passos '$t'"
            }
            # Secao Evolucoes lista apenas as selecionadas.
            $listadas = @([regex]::Matches($readme, '(?m)^- \*\*(.+?)\*\*: ') | ForEach-Object { $_.Groups[1].Value })
            $listadas.Count | Should -Be @($Titulos + $Pre | Select-Object -Unique).Count -Because $Ctx
        }
    }

    It 'adiciona cada evolução uma vez (README e roteiro), preserva o conteúdo e é idempotente (>= 100 iterações)' {
        [void](Initialize-Gerador -Contexto 'Property 21 (Add-Evolucoes)')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $raiz = Join-Path $TestDrive "p21-$i"
            $semente = Get-SementeAtual

            $readmeBase = (New-Readme).Texto
            # As vezes o README ja tem a secao Evolucoes com uma linha pre-existente.
            $pre = @()
            $roteiroBase = "# Roteiro`n`n" + (New-Frase -MinPalavras 0 -MaxPalavras 10) + "`n`n" +
                ((1..9 | ForEach-Object { "$_. **Passo $_ $(New-Frase -MinPalavras 1 -MaxPalavras 4).**`n   - Ação: $(New-Frase -MinPalavras 1 -MaxPalavras 6)" }) -join "`n") + "`n"
            Write-ArquivoUtf8 (Join-Path $raiz 'docs/evolucoes.md') $script:EvolucoesReal21
            $validos = @(Get-EvolucoesDisponiveis -Raiz $raiz)
            $titulos = @($validos | ForEach-Object { $_.Titulo })
            if (New-Booleano) {
                $d0 = Select-Aleatorio $validos
                $pre = @($d0.Titulo)
                $readmeBase = $readmeBase.TrimEnd("`r", "`n") + "`n`n## Evoluções`n`n- **$($d0.Titulo)**: $($d0.Descricao)`n"
            }
            Write-ArquivoUtf8 (Join-Path $raiz 'README.md') $readmeBase
            Write-ArquivoUtf8 (Join-Path $raiz 'docs/roteiro-manual.md') $roteiroBase

            # Pedido 1: 1 a 4 evolucoes distintas, em ordem aleatoria (possivelmente com repeticao).
            $n1 = New-Inteiro -Min 1 -Max 4
            $pedido1 = @($titulos | Sort-Object { (Get-Rng).Next() } | Select-Object -First $n1)
            if ($n1 -lt 4 -and (New-Booleano)) { $pedido1 += $pedido1[0] }
            $ctx = "iteração $i, semente base $semente, pedido1=[$($pedido1 -join '; ')]"

            $r1 = Add-Evolucoes -Raiz $raiz -Nomes $pedido1
            $r1.Sucesso | Should -BeTrue -Because "$ctx; $($r1.Motivo)"
            $unicos1 = @($pedido1 | Select-Object -Unique)
            @($r1.Adicionadas).Count | Should -Be $unicos1.Count -Because $ctx
            @($r1.JaExistentes).Count | Should -Be 0 -Because $ctx
            Assert-EstadoEvolucoes -Raiz $raiz -Titulos $unicos1 -Disponiveis $validos -RoteiroOriginal $roteiroBase -ReadmeOriginal $readmeBase -Pre $pre -Ctx $ctx

            # Idempotencia: repetir o mesmo pedido nao altera nada e informa que ja existiam.
            $antes = (Get-HashArvore -Raiz $raiz) -join "`n"
            $r2 = Add-Evolucoes -Raiz $raiz -Nomes $pedido1
            $r2.Sucesso | Should -BeTrue -Because "$ctx; $($r2.Motivo)"
            @($r2.Adicionadas).Count | Should -Be 0 -Because $ctx
            @($r2.JaExistentes).Count | Should -Be $unicos1.Count -Because $ctx
            $r2.Motivo | Should -Match 'ja foram adicionadas' -Because $ctx
            ((Get-HashArvore -Raiz $raiz) -join "`n") | Should -BeExactly $antes -Because $ctx

            # Pedido 2 sobreposto: so as novas sao adicionadas; as existentes sao informadas.
            $n2 = New-Inteiro -Min 1 -Max 4
            $pedido2 = @($titulos | Sort-Object { (Get-Rng).Next() } | Select-Object -First $n2)
            $novas2 = @($pedido2 | Where-Object { $unicos1 -cnotcontains $_ })
            $exist2 = @($pedido2 | Where-Object { $unicos1 -ccontains $_ })
            $r3 = Add-Evolucoes -Raiz $raiz -Nomes $pedido2
            $r3.Sucesso | Should -BeTrue -Because "$ctx; pedido2=[$($pedido2 -join '; ')]; $($r3.Motivo)"
            @($r3.Adicionadas | Sort-Object) -join ',' | Should -BeExactly (@($novas2 | Sort-Object) -join ',') -Because $ctx
            @($r3.JaExistentes | Sort-Object) -join ',' | Should -BeExactly (@($exist2 | Sort-Object) -join ',') -Because $ctx
            $uniao = @($unicos1 + $novas2 | Select-Object -Unique)
            Assert-EstadoEvolucoes -Raiz $raiz -Titulos $uniao -Disponiveis $validos -RoteiroOriginal $roteiroBase -ReadmeOriginal $readmeBase -Pre $pre -Ctx "$ctx; pedido2=[$($pedido2 -join '; ')]"
        }
    }
}
