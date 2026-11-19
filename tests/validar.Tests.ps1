# Testes de propriedade do Validador (Pester 5).
# Feature: axios-segundo-cerebro
# Rodar: Invoke-Pester ./tests/validar.Tests.ps1
# Para reproduzir uma falha: $env:AXIOS_SEED = <semente impressa no inicio do teste>.
# Cada Describe cobre uma propriedade do design.md ("Correctness Properties").

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'scripts' 'validar.ps1')
    . (Join-Path $PSScriptRoot 'Gerador.ps1')
    $script:Iteracoes = 100
}

Describe 'Property 1: Links relativos quebrados são exatamente os que não resolvem' {
    # Feature: axios-segundo-cerebro, Property 1: Links relativos quebrados são exatamente os que não resolvem
    # **Validates: Requirements 3.6, 3.7, 10.3**

    It 'Get-LinksRelativos e Find-LinksQuebrados batem com o conjunto de arquivos (>= 100 iterações)' {
        [void](Initialize-Gerador -Contexto 'Property 1')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $raiz = Join-Path $TestDrive "p1-$i"
            New-Item -ItemType Directory -Force -Path $raiz | Out-Null
            $g = New-MarkdownComLinks -Raiz $raiz -MinLinks 0 -MaxLinks 12
            $semente = Get-SementeAtual
            $ctx = "iteração $i, semente base $semente"

            # Esperado, calculado a partir do que o gerador produziu (não do Validador).
            $mailto = @([regex]::Matches($g.Texto, '\]\((mailto:[^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value })
            $esperadoRelativos = @($g.Existentes) + @($g.Inexistentes) + @($g.Pastas) + $mailto
            # Pastas e mailto não resolvem para arquivo, portanto também são quebrados.
            $esperadoQuebrados = @($g.Inexistentes) + @($g.Pastas) + $mailto

            # Remove ancora/consulta e decodifica %20 (mesma regra de normalizacao do design).
            $limpar = { param($d) ($d -replace '[#?].*$', '') -replace '%20', ' ' }

            $relativos = @(Get-LinksRelativos -Texto $g.Texto)
            $quebrados = @(Find-LinksQuebrados -Raiz $raiz -TextoReadme $g.Texto)

            # Nenhum destino externo ou âncora pode aparecer entre os relativos.
            foreach ($r in $relativos) { $r | Should -Not -Match '^(https?://|#)' -Because $ctx }

            $relLimpos = @($relativos | ForEach-Object { & $limpar $_ } | Sort-Object)
            $quebLimpos = @($quebrados | ForEach-Object { & $limpar $_ } | Sort-Object)

            ($relLimpos -join '|') | Should -BeExactly ((@($esperadoRelativos) | Sort-Object) -join '|') -Because $ctx
            ($quebLimpos -join '|') | Should -BeExactly ((@($esperadoQuebrados) | Sort-Object) -join '|') -Because $ctx

            # Quebrados é subconjunto dos relativos.
            $quebrados.Count | Should -BeLessOrEqual $relativos.Count -Because $ctx
        }
    }

    It 'retorna listas vazias para texto sem links' {
        @(Get-LinksRelativos -Texto '').Count | Should -Be 0
        @(Find-LinksQuebrados -Raiz $TestDrive -TextoReadme 'sem links aqui').Count | Should -Be 0
    }
}

Describe 'Property 2: Arquivos citados vazios são exatamente os de 0 bytes' {
    # Feature: axios-segundo-cerebro, Property 2: Arquivos citados vazios são exatamente os de 0 bytes
    # **Validates: Requirements 10.4**

    It 'Find-ArquivosVazios retorna só os existentes com 0 bytes (>= 100 iterações)' {
        [void](Initialize-Gerador -Contexto 'Property 2')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $raiz = Join-Path $TestDrive "p2-$i"
            New-Item -ItemType Directory -Force -Path (Join-Path $raiz 'docs') | Out-Null
            $ctx = "iteração $i, semente base $(Get-SementeAtual)"

            $n = New-Inteiro -Min 0 -Max 12
            $texto = [System.Text.StringBuilder]::new()
            $citados = New-Object System.Collections.Generic.List[string]
            $esperadoVazios = New-Object System.Collections.Generic.List[string]

            for ($k = 0; $k -lt $n; $k++) {
                # Sufixo com índice garante nomes distintos; ext .md/.txt.
                $pasta = Select-Aleatorio @('', 'docs/')
                $nome = "$pasta$(New-Palavra -Min 2 -Max 8)-$k.$(Select-Aleatorio @('md', 'txt'))"
                $existe = (New-Inteiro -Min 0 -Max 4) -ne 0
                if ($existe) {
                    $tam = if (New-Booleano) { 0 } else { New-Inteiro -Min 1 -Max 64 }
                    $bytes = [byte[]]::new($tam)
                    for ($b = 0; $b -lt $tam; $b++) { $bytes[$b] = [byte](New-Inteiro -Min 65 -Max 90) }
                    [System.IO.File]::WriteAllBytes((Join-Path $raiz $nome), $bytes)
                    if ($tam -eq 0) { $esperadoVazios.Add($nome) }
                }
                $citados.Add($nome)
                if (New-Booleano) { [void]$texto.AppendLine("Veja [fonte $k]($nome) agora.") }
                else { [void]$texto.AppendLine("Veja ``$nome`` agora.") }
            }

            $obtidosCitados = @(Get-CaminhosCitados -Texto $texto.ToString())
            (($obtidosCitados | Sort-Object) -join '|') | Should -BeExactly ((@($citados) | Sort-Object) -join '|') -Because $ctx

            $vazios = @(Find-ArquivosVazios -Raiz $raiz -Caminhos $obtidosCitados)
            (($vazios | Sort-Object) -join '|') | Should -BeExactly ((@($esperadoVazios) | Sort-Object) -join '|') -Because $ctx
        }
    }

    It 'retorna lista vazia sem caminhos' {
        $r = Find-ArquivosVazios -Raiz $TestDrive -Caminhos @()
        @($r).Count | Should -Be 0
    }
}

Describe 'Property 3: Seções obrigatórias' {
    # Feature: axios-segundo-cerebro, Property 3: Seções obrigatórias
    # **Validates: Requirements 3.1, 10.5**

    It 'Find-SecoesFaltantes é vazio com as cinco seções em ordem e não vazio após remover, duplicar, renomear ou trocar ordem (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 3'
        $obrigatorias = @($script:TitulosSecoes)
        $mutacoes = @('Remover', 'Duplicar', 'Renomear', 'TrocarOrdem', 'Nenhuma')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $mutacao = $mutacoes[$i % $mutacoes.Count]   # cobre todas as mutações de forma uniforme
            $numerado = New-Booleano
            $glossario = New-Booleano
            $readme = if ($numerado -and $glossario) { New-Readme -Numerado -ComGlossario }
                      elseif ($numerado) { New-Readme -Numerado }
                      elseif ($glossario) { New-Readme -ComGlossario }
                      else { New-Readme }

            # Seções extras depois das cinco (nunca com título obrigatório).
            $extras = New-Inteiro -Min 0 -Max 3
            for ($e = 0; $e -lt $extras; $e++) {
                $readme.Secoes.Add([pscustomobject]@{ Titulo = 'Extra ' + (New-Palavra); Corpo = (New-Frase); Numeracao = '' })
            }

            $ctx = "iteração $i, mutação $mutacao, numerado=$numerado, glossário=$glossario, extras=$extras, semente base $semente"

            if ($mutacao -eq 'Nenhuma') {
                # README sem mutação, com a numeração gerada (ou sem).
                $texto = ConvertTo-TextoReadme $readme.Secoes
                @(Find-SecoesFaltantes -TextoReadme $texto).Count | Should -Be 0 -Because $ctx
                continue
            }

            $m = Edit-ReadmeMutacao -Readme $readme -Mutacao $mutacao
            $m.Valido | Should -BeFalse -Because $ctx

            $resultado = @(Find-SecoesFaltantes -TextoReadme $m.Texto)
            $resultado.Count | Should -BeGreaterThan 0 -Because $ctx

            # Todo item retornado é uma das cinco seções obrigatórias.
            foreach ($r in $resultado) { $obrigatorias | Should -Contain $r -Because $ctx }

            # A seção afetada é identificada: para remover, duplicar e renomear, toda obrigatória
            # que não aparece exatamente uma vez (comparação exata) deve estar no resultado.
            if ($mutacao -ne 'TrocarOrdem') {
                $titulos = @($m.Secoes | ForEach-Object { $_.Titulo })
                foreach ($nome in $obrigatorias) {
                    $vezes = @($titulos | Where-Object { $_ -ceq $nome }).Count
                    if ($vezes -ne 1) { $resultado | Should -Contain $nome -Because $ctx }
                }
            }
        }
    }

    It 'aceita as cinco seções com e sem numeração e rejeita README vazio' {
        @(Find-SecoesFaltantes -TextoReadme (New-Readme).Texto).Count | Should -Be 0
        @(Find-SecoesFaltantes -TextoReadme (New-Readme -Numerado -ComGlossario).Texto).Count | Should -Be 0
        @(Find-SecoesFaltantes -TextoReadme '').Count | Should -Be 5
    }
}

Describe 'Property 4: Detecção de Placeholder' {
    # Feature: axios-segundo-cerebro, Property 4: Detecção de Placeholder
    # **Validates: Requirements 10.6**

    It 'Find-Placeholders retorna exatamente os Placeholders inseridos (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 4'
        $proibidas = @('todo', 'tbd', 'xxx', 'lorem', 'ipsum', 'preencher')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            # Palavras alfanuméricas sem os termos (palavra inteira TODO/TBD/XXX, lorem, ipsum).
            $nPalavras = New-Inteiro -Min 0 -Max 15
            $itens = New-Object System.Collections.Generic.List[string]
            for ($k = 0; $k -lt $nPalavras; $k++) {
                do { $w = New-Palavra -Min 1 -Max 10 } while ($proibidas -contains $w)
                $itens.Add($w)
            }

            # Metade das iterações não insere nenhum Placeholder.
            $inseridos = New-Object System.Collections.Generic.List[string]
            $nPh = if ($i % 2 -eq 0) { 0 } else { New-Inteiro -Min 1 -Max 6 }
            for ($k = 0; $k -lt $nPh; $k++) {
                $ph = New-Placeholder
                $inseridos.Add($ph)
                $itens.Insert((New-Inteiro -Min 0 -Max $itens.Count), $ph)
            }

            $texto = $itens -join ' '
            $ctx = "iteração $i, inseridos=$($inseridos.Count), semente base $semente, texto='$texto'"

            $achados = @(Find-Placeholders -Texto $texto)
            $achados.Count | Should -Be $inseridos.Count -Because $ctx
            (($achados | Sort-Object { $_ } -CaseSensitive) -join '|') |
                Should -BeExactly ((@($inseridos) | Sort-Object { $_ } -CaseSensitive) -join '|') -Because $ctx
        }
    }

    It 'detecta os cinco termos e ignora texto sem Placeholder' {
        @(Find-Placeholders -Texto '[PREENCHER: algo] todo TBD xXx Lorem   Ipsum').Count | Should -Be 5
        @(Find-Placeholders -Texto 'metodo todos xxxl tbdx').Count | Should -Be 0
        @(Find-Placeholders -Texto '').Count | Should -Be 0
    }
}

Describe 'Property 5: Validação do Link do Notebook' {
    # Feature: axios-segundo-cerebro, Property 5: Validação do Link do Notebook
    # **Validates: Requirements 9.1, 9.5, 10.7**

    BeforeAll {
        # Prefixo "u" em cada segmento impede que palavras sorteadas virem TODO/TBD/XXX/lorem.
        function New-UrlTeste {
            param([string]$Esquema = 'https://')
            $host1 = 'u' + (New-Palavra -Min 2 -Max 8)
            $segs = @(1..(New-Inteiro -Min 0 -Max 3) | ForEach-Object { 'u' + (New-Palavra -Min 1 -Max 8) })
            return $Esquema + $host1 + '.example' + ($(if ($segs.Count) { '/' + ($segs -join '/') } else { '' }))
        }

        # Texto sem URL e sem Placeholder.
        function New-ProsaSegura {
            do { $t = New-Frase -MinPalavras 0 -MaxPalavras 8 } while (@(Find-Placeholders -Texto $t).Count -gt 0)
            return $t
        }

        # Embrulha a URL em formas comuns de escrita no README.
        function Format-UrlNoCorpo {
            param([string]$Url)
            $prosa = New-ProsaSegura
            switch (New-Inteiro -Min 0 -Max 3) {
                0 { return $Url }
                1 { return "<$Url>" }
                2 { return "[abrir notebook]($Url)" }
                default { return "$prosa $Url." }
            }
        }
    }

    It 'é válido somente com exatamente uma URL https:// e nenhum Placeholder (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 5'
        $casos = @('Valida', 'ZeroUrls', 'DuasOuMais', 'Http', 'OutroEsquema', 'Vazia', 'Ausente', 'Placeholder')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $caso = $casos[$i % $casos.Count]   # cobre todos os casos de forma uniforme
            $titulo = 'Link do notebook'
            $esperado = $false
            $corpo = ''

            switch ($caso) {
                'Valida' { $corpo = Format-UrlNoCorpo (New-UrlTeste); $esperado = $true }
                'ZeroUrls' { $corpo = New-ProsaSegura; if ([string]::IsNullOrWhiteSpace($corpo)) { $corpo = 'sem link' } }
                'DuasOuMais' {
                    $n = New-Inteiro -Min 2 -Max 4
                    $corpo = (1..$n | ForEach-Object { Format-UrlNoCorpo (New-UrlTeste) }) -join "`n"
                }
                'Http' {
                    $corpo = Format-UrlNoCorpo (New-UrlTeste -Esquema 'http://')
                    if (New-Booleano) { $corpo = $corpo + "`n" + (Format-UrlNoCorpo (New-UrlTeste)) }
                }
                'OutroEsquema' {
                    $esq = Select-Aleatorio @('ftp://', 'file://', 'ssh://', 'ws://')
                    $corpo = Format-UrlNoCorpo (New-UrlTeste -Esquema $esq)
                }
                'Vazia' { $corpo = Select-Aleatorio @('', ' ', "`n", '   ') }
                'Placeholder' {
                    $url = Format-UrlNoCorpo (New-UrlTeste)
                    $ph = New-Placeholder
                    $corpo = if (New-Booleano) { "$url $ph" } else { "$ph`n$url" }
                }
            }

            # Seções vizinhas podem conter URLs http e Placeholders: só o corpo da seção conta.
            $corpos = @{ $titulo = $corpo }
            $glossario = New-Booleano
            $readme = if ($caso -eq 'Ausente') { New-Readme } else { New-Readme -Corpos $corpos -ComGlossario:$glossario }
            if ($caso -ne 'Ausente') {
                foreach ($s in $readme.Secoes) {
                    if ($s.Titulo -ne $titulo -and (New-Booleano)) {
                        $s.Corpo = $s.Corpo + "`n" + (New-UrlTeste -Esquema (Select-Aleatorio @('http://', 'https://'))) + ' ' + (New-Placeholder)
                    }
                }
            }
            else {
                $readme.Secoes.RemoveAll([Predicate[object]] { param($s) $s.Titulo -ceq 'Link do notebook' }) | Out-Null
            }
            $texto = ConvertTo-TextoReadme $readme.Secoes
            if ($caso -eq 'Ausente' -and (New-Inteiro -Min 0 -Max 4) -eq 0) { $texto = '' }

            $ctx = "iteração $i, caso $caso, semente base $semente, corpo='$corpo'"
            $r = Test-LinkNotebook -TextoReadme $texto
            $r.Valido | Should -Be $esperado -Because $ctx
            if (-not $esperado) { $r.Motivo | Should -Match 'Link do Notebook inválido' -Because $ctx }

            # Requirement 9.5: a verificação não altera o texto recebido (mesma entrada, mesmo resultado).
            $r2 = Test-LinkNotebook -TextoReadme $texto
            $r2.Valido | Should -Be $r.Valido -Because $ctx
        }
    }

    It 'trata texto nulo, vazio e sem a seção como inválido' {
        (Test-LinkNotebook -TextoReadme '').Valido | Should -BeFalse
        (Test-LinkNotebook -TextoReadme $null).Valido | Should -BeFalse
        (Test-LinkNotebook -TextoReadme "# T`n`n## Outra`n`nhttps://a.example").Valido | Should -BeFalse
    }
}

Describe 'Property 6: Termos proibidos' {
    # Feature: axios-segundo-cerebro, Property 6: Termos proibidos
    # **Validates: Requirements 3.5, 10.8**
    # Decisão do usuário (altera o design): o termo casa só como palavra/expressão inteira
    # (limites = letras e dígitos Unicode), sem diferenciar maiúsculas de minúsculas.

    BeforeAll {
        # Letras acentuadas criadas por ponto de código (á é ç ã ñ ü); nunca literais no arquivo.
        $script:LetrasAcento = @(0x00E1, 0x00E9, 0x00E7, 0x00E3, 0x00F1, 0x00FC) | ForEach-Object { [char]::ConvertFromUtf32($_) }

        # Termo sintético com acentos, montado em tempo de execução.
        function New-TermoAcentuado {
            $partes = @('q', 'z', 'x', (New-Palavra -Min 2 -Max 4), (Select-Aleatorio $script:LetrasAcento), (New-Palavra -Min 2 -Max 4))
            return (Join-Partes $partes)
        }

        # Caractere que "cola" no termo e impede o casamento (letra, dígito ou letra acentuada).
        function New-CharColante {
            return [string](Select-Aleatorio (@([char[]]'abcxyzABCXYZ0123456789') + @($script:LetrasAcento)))
        }
    }

    It 'Find-TermosProibidos retorna exatamente os termos presentes como palavra inteira (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 6'

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            # Termos distintos e sem um conter o outro (evita casamento cruzado legítimo).
            do {
                $lista = New-ListaTermosProibidos -Min 1 -Max 4
                $termos = @($lista.Termos)
                if (New-Booleano) { $termos += New-TermoAcentuado }
                if ((New-Inteiro -Min 0 -Max 3) -eq 0) {
                    # Expressão de duas palavras (termo composto).
                    $termos += (Join-Partes @((New-TermoProibidoSintetico), ' ', (New-TermoProibidoSintetico)))
                }
                $ok = $true
                foreach ($a in $termos) {
                    foreach ($b in $termos) {
                        if (-not [object]::ReferenceEquals($a, $b) -and $a -ne $b -and $a.ToLowerInvariant().Contains($b.ToLowerInvariant())) { $ok = $false }
                    }
                }
                if (@($termos | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique).Count -ne $termos.Count) { $ok = $false }
            } while (-not $ok)

            # Linhas da lista: termos com espaços nas pontas, linhas em branco e só com espaços.
            $linhas = @()
            foreach ($t in $termos) {
                $linhas += ((' ' * (New-Inteiro -Min 0 -Max 2)) + $t + (' ' * (New-Inteiro -Min 0 -Max 2)))
                if (New-Booleano) { $linhas += (Select-Aleatorio @('', ' ', "`t")) }
            }

            # Monta o texto: cada termo é presente (simples ou com pontuação), colado ou ausente.
            $itens = New-Object System.Collections.Generic.List[string]
            $esperado = New-Object System.Collections.Generic.List[string]
            $planos = New-Object System.Collections.Generic.List[string]
            foreach ($t in $termos) {
                $plano = Select-Aleatorio @('Presente', 'Pontuacao', 'ColadoPrefixo', 'ColadoSufixo', 'ColadoAmbos', 'Ausente')
                $planos.Add($plano)
                $caixa = Set-CaixaAleatoria $t
                switch ($plano) {
                    'Presente' { $itens.Add($caixa); $esperado.Add($t) }
                    'Pontuacao' {
                        $moldura = Select-Aleatorio @('({0})', '"{0}"', '{0}.', '{0},', '{0};', '[{0}]', '-{0}-', '{0}!', '{0}?', '<{0}>')
                        $itens.Add(($moldura -f $caixa)); $esperado.Add($t)
                    }
                    'ColadoPrefixo' { $itens.Add((New-CharColante) + $caixa) }
                    'ColadoSufixo' { $itens.Add($caixa + (New-CharColante)) }
                    'ColadoAmbos' { $itens.Add((New-CharColante) + $caixa + (New-CharColante)) }
                    'Ausente' { }
                }
            }
            $nFiller = New-Inteiro -Min 0 -Max 8
            for ($k = 0; $k -lt $nFiller; $k++) { $itens.Insert((New-Inteiro -Min 0 -Max $itens.Count), (New-Palavra -Min 1 -Max 8)) }
            $texto = $itens -join (Select-Aleatorio @(' ', "`n", ' '))

            $ctx = "iteração $i, semente base $semente, planos=$($planos -join ','), termos=$($termos -join '|'), texto='$texto'"
            $achados = @(Find-TermosProibidos -Texto $texto -Termos $linhas)

            (($achados | Sort-Object) -join '|') | Should -BeExactly ((@($esperado) | Sort-Object) -join '|') -Because $ctx
        }
    }

    It 'ignora linhas em branco e texto vazio' {
        @(Find-TermosProibidos -Texto 'qualquer texto' -Termos @('', '   ', "`t")).Count | Should -Be 0
        @(Find-TermosProibidos -Texto '' -Termos @('abc')).Count | Should -Be 0
        @(Find-TermosProibidos -Texto 'abc' -Termos @()).Count | Should -Be 0
    }

    It 'casa palavra inteira sem diferenciar caixa e não casa dentro de palavra maior' {
        $t = Join-Partes @('q', 'z', 'x', 'abc')
        @(Find-TermosProibidos -Texto ('ver ' + $t.ToUpperInvariant() + '.') -Termos @($t)).Count | Should -Be 1
        @(Find-TermosProibidos -Texto ('ver a' + $t) -Termos @($t)).Count | Should -Be 0
        @(Find-TermosProibidos -Texto ('ver ' + $t + '9') -Termos @($t)).Count | Should -Be 0
    }
}

Describe 'Property 7: Convenção de nomes de arquivo' {
    # Feature: axios-segundo-cerebro, Property 7: Convenção de nomes de arquivo
    # **Validates: Requirements 8.6**

    BeforeAll {
        # Oráculo independente: regex ECMAScript (classes ASCII estritas) + limite de comprimento.
        function Get-EsperadoNomeMaterial {
            param([string]$Nome)
            if ($Nome.Length -gt 100) { return $false }
            return [regex]::IsMatch($Nome, '\A[a-z0-9\-]+\.[a-z0-9]+\z', [System.Text.RegularExpressions.RegexOptions]::ECMAScript)
        }
    }

    It 'Test-NomeArquivoMaterial é verdadeiro exatamente para nomes que casam a regex com até 100 caracteres (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 7'
        $casos = @('Valido', 'Gerado', 'GeradoComExt', 'Maiuscula', 'Underscore', 'Espaco', 'Simbolo', 'Unicode',
            'SemExtensao', 'VariosPontos', 'Longo101', 'Limite100', 'PontoFinal', 'QuebraLinha')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $caso = $casos[$i % $casos.Count]   # cobre todos os casos de forma uniforme
            $valido = New-NomeValidoMaterial
            $ponto = $valido.LastIndexOf('.')
            $base = $valido.Substring(0, $ponto)
            $ext = $valido.Substring($ponto + 1)
            $nome = switch ($caso) {
                'Valido' { $valido }
                'Gerado' { New-NomeArquivo -MinComprimento 1 -MaxComprimento 150 }
                'GeradoComExt' { New-NomeArquivo -MinComprimento 1 -MaxComprimento 150 -ComExtensao }
                'Maiuscula' { $p = New-Inteiro -Min 0 -Max ($valido.Length - 1); $valido.Substring(0, $p) + $valido.Substring($p, 1).ToUpperInvariant() + $valido.Substring($p + 1) + 'A' }
                'Underscore' { $p = New-Inteiro -Min 0 -Max $base.Length; $base.Insert($p, '_') + '.' + $ext }
                'Espaco' { $p = New-Inteiro -Min 0 -Max $base.Length; $base.Insert($p, ' ') + '.' + $ext }
                'Simbolo' { $p = New-Inteiro -Min 0 -Max $base.Length; $base.Insert($p, [string](Select-Aleatorio @('!', '#', '@', '+', '(', '&', '%', '$'))) + '.' + $ext }
                'Unicode' { $p = New-Inteiro -Min 0 -Max $base.Length; $base.Insert($p, (New-StringAleatoria -MinComprimento 1 -MaxComprimento 2 -Alfabeto Unicode)) + '.' + $ext }
                'SemExtensao' { $base }
                'VariosPontos' { $base + '.' + (New-Palavra -Min 1 -Max 3) + '.' + $ext }
                'Longo101' { ('a' * (101 - $ext.Length - 1 + (New-Inteiro -Min 0 -Max 49))) + '.' + $ext }
                'Limite100' { ('a' * (100 - $ext.Length - 1 + (New-Inteiro -Min 0 -Max 1))) + '.' + $ext }
                'PontoFinal' { $base + '.' }
                'QuebraLinha' { $valido + "`n" }
            }

            $esperado = Get-EsperadoNomeMaterial $nome
            $ctx = "iteração $i, caso $caso, semente base $semente, comprimento=$($nome.Length), nome='$nome'"
            (Test-NomeArquivoMaterial -Nome $nome) | Should -Be $esperado -Because $ctx

            # Todo nome de New-NomeValidoMaterial é válido pelo oráculo e pelo Validador.
            (Test-NomeArquivoMaterial -Nome $valido) | Should -BeTrue -Because "$ctx, valido='$valido'"
        }
    }

    It 'trata os limites de 100 e 101 caracteres, vazio e nulo' {
        (Test-NomeArquivoMaterial -Nome (('a' * 96) + '.txt')) | Should -BeTrue
        (Test-NomeArquivoMaterial -Nome (('a' * 97) + '.txt')) | Should -BeFalse
        (Test-NomeArquivoMaterial -Nome '') | Should -BeFalse
        (Test-NomeArquivoMaterial -Nome $null) | Should -BeFalse
        (Test-NomeArquivoMaterial -Nome 'a-b.png') | Should -BeTrue
        (Test-NomeArquivoMaterial -Nome 'a_b.png') | Should -BeFalse
    }
}

Describe 'Property 8: Nome sugerido é válido e estável' {
    # Feature: axios-segundo-cerebro, Property 8: Nome sugerido é válido e estável
    # **Validates: Requirements 8.7**

    It 'Get-NomeSugerido devolve nome válido, com até 100 caracteres, extensão preservada e idempotente (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 8'
        $casos = @('Gerado', 'ExtCurta', 'ExtMaiuscula', 'ExtLonga', 'SoSimbolos', 'JaValido')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $caso = $casos[$i % $casos.Count]
            $extEsperada = $null
            $nome = switch ($caso) {
                'Gerado' { New-NomeArquivo -MinComprimento 3 -MaxComprimento 150 -ComExtensao }
                'ExtCurta' { New-NomeArquivo -MinComprimento 3 -MaxComprimento 150 -ComExtensao }
                'ExtMaiuscula' { (New-NomeArquivo -MinComprimento 1 -MaxComprimento 120) + '.' + (New-Palavra -Min 1 -Max 4).ToUpperInvariant() }
                'ExtLonga' { (New-NomeArquivo -MinComprimento 1 -MaxComprimento 50) + '.' + (New-Palavra -Min 90 -Max 150) }
                'SoSimbolos' { (New-StringAleatoria -MinComprimento 1 -MaxComprimento 20 -Alfabeto Unicode) + '!@# _' + '.' + (New-Palavra -Min 1 -Max 4) }
                'JaValido' { New-NomeValidoMaterial }
            }
            $ponto = $nome.LastIndexOf('.')
            $extEsperada = $nome.Substring($ponto + 1).ToLowerInvariant()
            # Nome base sem nenhum alfanumérico (ex.: só símbolos Unicode) é coberto pelo texto-padrão 'arquivo'.

            $ctx = "iteração $i, caso $caso, semente base $semente, nome='$nome'"
            $sug = Get-NomeSugerido -Nome $nome

            (Test-NomeArquivoMaterial -Nome $sug) | Should -BeTrue -Because "$ctx, sugerido='$sug'"
            $sug.Length | Should -BeLessOrEqual 100 -Because "$ctx, sugerido='$sug'"

            $extSug = $sug.Substring($sug.LastIndexOf('.') + 1)
            if ($extEsperada.Length -le 98) { $extSug | Should -BeExactly $extEsperada -Because "$ctx, sugerido='$sug'" }
            else { $extEsperada.StartsWith($extSug, [System.StringComparison]::Ordinal) | Should -BeTrue -Because "$ctx, sugerido='$sug'" }

            (Get-NomeSugerido -Nome $sug) | Should -BeExactly $sug -Because "$ctx, idempotência, sugerido='$sug'"
            if ($caso -eq 'JaValido') { $sug | Should -BeExactly $nome -Because $ctx }
        }
    }
}

Describe 'Property 9: Formato da saída e código de saída' {

    # Feature: axios-segundo-cerebro, Property 9: Formato da saída e código de saída
    # **Validates: Requirements 10.9, 10.10, 10.11**

    It 'Get-CodigoSaida é 0 se e somente se todos os resultados são OK (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 9 (código de saída)'
        Write-Host "Property 9 (código de saída): semente base $semente"

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $n = New-Inteiro -Min 0 -Max 6
            $resultados = @(for ($k = 1; $k -le $n; $k++) {
                [pscustomobject]@{ Id = $k; Descricao = (New-Frase -MinPalavras 1 -MaxPalavras 5); Ok = (New-Booleano); Detalhes = @() }
            })
            $todosOk = (@($resultados | Where-Object { -not $_.Ok }).Count -eq 0)
            $esperado = if ($todosOk) { 0 } else { 1 }
            $ctx = "iteração $i, n=$n, Ok=[$((@($resultados | ForEach-Object { $_.Ok })) -join ',')], semente base $semente"

            (Get-CodigoSaida -Resultados $resultados) | Should -Be $esperado -Because $ctx
        }
    }

    It 'Invoke-Validacao retorna 6 resultados na ordem do design, em repositórios sintéticos com falhas aleatórias (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 9 (Invoke-Validacao)'
        Write-Host "Property 9 (Invoke-Validacao): semente base $semente"

        $termo = Join-Partes 'q', 'z', 'x', 'proibido', 'teste'
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $secoes = @(
            '## 1. Tema e objetivo', '## 2. Fontes e por que são confiáveis', '## 3. Diretriz de comportamento',
            '## 4. Perguntas, respostas e fontes', '## 5. Link do notebook'
        )
        $descricoes = @(
            'Links relativos do README apontam para arquivos existentes',
            'Arquivos citados no README têm mais de 0 bytes',
            'README contém as cinco seções obrigatórias',
            'README e docs/*.md sem Termos_de_Placeholder',
            'Link do Notebook começa com https://',
            'Arquivos de texto sem termos proibidos'
        )
        $pwsh = (Get-Process -Id $PID).Path
        $script:P9Repos = @()

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $raiz = Join-Path $TestDrive "p9-$i"
            New-Item -ItemType Directory -Force -Path (Join-Path $raiz 'scripts'), (Join-Path $raiz 'docs') | Out-Null

            # Falhas aleatórias: uma flag por verificação (1 a 6).
            $falha = @{}
            foreach ($id in 1..6) { $falha[$id] = (New-Booleano) }

            $corpo = [System.Text.StringBuilder]::new()
            [void]$corpo.AppendLine('# Repositório sintético')
            foreach ($s in $secoes) {
                if ($falha[3] -and $s -like '## 3.*') { continue }
                [void]$corpo.AppendLine()
                [void]$corpo.AppendLine($s)
                [void]$corpo.AppendLine()
                if ($s -like '## 2.*') {
                    [void]$corpo.AppendLine('Veja o [registro](docs/fontes.md).')
                    if ($falha[1]) { [void]$corpo.AppendLine('Veja [sumido](docs/nao-existe.md).') }
                    if ($falha[2]) { [void]$corpo.AppendLine('Veja [vazio](docs/vazio.md).') }
                }
                elseif ($s -like '## 5.*') {
                    $url = if ($falha[5]) { 'http://notebook.example/abc' } else { 'https://notebook.example/abc' }
                    [void]$corpo.AppendLine($url)
                }
                else { [void]$corpo.AppendLine('Texto simples.') }
            }
            $fontes = 'Registro de fontes de exemplo.'
            if ($falha[4]) { $fontes += ' TBD' }
            [System.IO.File]::WriteAllText((Join-Path $raiz 'README.md'), $corpo.ToString(), $utf8)
            [System.IO.File]::WriteAllText((Join-Path $raiz 'docs/fontes.md'), $fontes + "`n", $utf8)
            if ($falha[2]) { [System.IO.File]::WriteAllText((Join-Path $raiz 'docs/vazio.md'), '', $utf8) }
            if ($falha[6]) { [System.IO.File]::WriteAllText((Join-Path $raiz 'docs/extra.md'), "contém $termo aqui`n", $utf8) }
            [System.IO.File]::WriteAllText((Join-Path $raiz 'scripts/termos-proibidos.txt'), "$termo`n", $utf8)

            $ctx = "iteração $i, falhas=[$((1..6 | Where-Object { $falha[$_] }) -join ',')], semente base $semente"
            $res = @(Invoke-Validacao -Raiz $raiz)

            $res.Count | Should -Be 6 -Because $ctx
            (@($res | ForEach-Object { $_.Id }) -join ',') | Should -BeExactly '1,2,3,4,5,6' -Because $ctx
            for ($k = 0; $k -lt 6; $k++) {
                $res[$k].Descricao | Should -BeExactly $descricoes[$k] -Because $ctx
                if ($falha[$res[$k].Id]) { $res[$k].Ok | Should -BeFalse -Because "$ctx, verificação $($res[$k].Id)" }
            }
            $todosOk = (@($res | Where-Object { -not $_.Ok }).Count -eq 0)
            (Get-CodigoSaida -Resultados $res) | Should -Be $(if ($todosOk) { 0 } else { 1 }) -Because $ctx
            if (-not (1..6 | Where-Object { $falha[$_] })) { $todosOk | Should -BeTrue -Because "$ctx, sem falhas injetadas" }

            # Parte de processo: só nas 8 primeiras iterações (custo de tempo).
            if ($i -lt 8) {
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..' 'scripts' 'validar.ps1') -Destination (Join-Path $raiz 'scripts' 'validar.ps1')
                $saida = & $pwsh -NoProfile -File (Join-Path $raiz 'scripts' 'validar.ps1') -Raiz $raiz 2>&1
                $codigo = $LASTEXITCODE
                $linhas = @($saida | ForEach-Object { "$_" })
                $statusLinhas = @($linhas | Where-Object { $_ -match '^(OK|FALHA)\s' })

                $statusLinhas.Count | Should -Be 6 -Because "$ctx (processo)"
                for ($k = 0; $k -lt 6; $k++) {
                    $rotulo = if ($res[$k].Ok) { 'OK' } else { 'FALHA' }
                    $statusLinhas[$k] | Should -Match "^$rotulo\s+$([regex]::Escape($descricoes[$k]))" -Because "$ctx (processo)"
                }
                $codigo | Should -Be $(if ($todosOk) { 0 } else { 1 }) -Because "$ctx (processo)"
            }
        }
    }
}

Describe 'Property 10: Todas as verificações executam, mesmo com arquivos ausentes' {

    # Feature: axios-segundo-cerebro, Property 10: Todas as verificações executam, mesmo com arquivos ausentes
    # **Validates: Requirements 10.12, 10.10**

    It 'README.md e termos-proibidos.txt ausentes, vazios ou só com espaços falham nas verificações dependentes e as demais executam (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 10'
        Write-Host "Property 10: semente base $semente"

        $estados = @('Presente', 'Ausente', 'Vazio', 'Espacos')
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $termo = Join-Partes 'q', 'z', 'x', 'proibido', 'teste'
        $readmeValido = @(
            '# Repositório sintético', '', '## 1. Tema e objetivo', '', 'Texto.', '',
            '## 2. Fontes e por que são confiáveis', '', 'Veja o [registro](docs/fontes.md).', '',
            '## 3. Diretriz de comportamento', '', 'Texto.', '',
            '## 4. Perguntas, respostas e fontes', '', 'Texto.', '',
            '## 5. Link do notebook', '', 'https://notebook.example/abc', ''
        ) -join "`n"

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $raiz = Join-Path $TestDrive "p10-$i"
            New-Item -ItemType Directory -Force -Path (Join-Path $raiz 'scripts'), (Join-Path $raiz 'docs') | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $raiz 'docs/fontes.md'), "Registro de fontes.`n", $utf8)

            # Garante cobertura dos 16 pares nas primeiras iterações; depois, aleatório.
            if ($i -lt 16) { $er = $estados[$i % 4]; $et = $estados[[int][math]::Floor($i / 4)] }
            else { $er = $estados[(New-Inteiro 0 3)]; $et = $estados[(New-Inteiro 0 3)] }

            $conteudo = @{ Vazio = ''; Espacos = "   `n`n `t `r`n  " }
            $arqs = @(
                @{ Estado = $er; Caminho = (Join-Path $raiz 'README.md'); Valido = $readmeValido },
                @{ Estado = $et; Caminho = (Join-Path $raiz 'scripts/termos-proibidos.txt'); Valido = "$termo`n" }
            )
            foreach ($a in $arqs) {
                if ($a.Estado -eq 'Presente') { [System.IO.File]::WriteAllText($a.Caminho, $a.Valido, $utf8) }
                elseif ($a.Estado -ne 'Ausente') { [System.IO.File]::WriteAllText($a.Caminho, $conteudo[$a.Estado], $utf8) }
            }

            $readmeFalta = ($er -ne 'Presente')
            $termosFalta = ($et -ne 'Presente')
            $ctx = "iteração $i, README=$er, termos=$et, semente base $semente"
            $res = @(Invoke-Validacao -Raiz $raiz)

            $res.Count | Should -Be 6 -Because $ctx
            (@($res | ForEach-Object { $_.Id }) -join ',') | Should -BeExactly '1,2,3,4,5,6' -Because $ctx
            foreach ($r in $res) {
                $dependeReadme = @(1, 2, 3, 5) -contains $r.Id
                $dependeTermos = ($r.Id -eq 6)
                $deveFalhar = (($dependeReadme -and $readmeFalta) -or ($dependeTermos -and $termosFalta))
                $r.Ok | Should -Be (-not $deveFalhar) -Because "$ctx, verificação $($r.Id)"
                if ($deveFalhar) {
                    $causa = if ($dependeReadme) { 'README.md ausente ou vazio' } else { 'termos-proibidos.txt ausente ou vazio' }
                    (@($r.Detalhes) -join ' | ') | Should -Match ([regex]::Escape($causa)) -Because "$ctx, verificação $($r.Id)"
                }
            }
            (Get-CodigoSaida -Resultados $res) | Should -Be $(if ($readmeFalta -or $termosFalta) { 1 } else { 0 }) -Because $ctx
        }
    }
}

Describe 'Property 11: O Validador não altera o repositório' {

    # Feature: axios-segundo-cerebro, Property 11: O Validador não altera o repositório
    # **Validates: Requirements 10.9, 9.5**

    It 'Invoke-Validacao mantém caminhos, tamanhos e hashes idênticos, inclusive .git e Link do Notebook inválido (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 11'
        Write-Host "Property 11: semente base $semente"

        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $links = @('', 'não é um link', 'ftp://exemplo.invalido/x', 'https://', 'http://a b', '<link>')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $raiz = Join-Path $TestDrive "p11-$i"
            $comGit = ($i % 2) -eq 0
            $arv = if ($comGit) { New-ArvoreArquivos -Raiz $raiz -MinArquivos 1 -MaxArquivos 8 -ComGit }
                   else { New-ArvoreArquivos -Raiz $raiz -MinArquivos 1 -MaxArquivos 8 }

            # Em parte das iterações, inclui README com Link do Notebook inválido.
            if (($i % 3) -ne 2) {
                $link = $links[$i % $links.Count]
                $readme = "# Sintético`n`n## 1. Tema e objetivo`n`nTexto.`n`n## 5. Link do notebook`n`n$link`n"
                [System.IO.File]::WriteAllText((Join-Path $raiz 'README.md'), $readme, $utf8)
            }

            $ctx = "iteração $i, comGit=$comGit, semente base $semente"
            $antes = @(Get-HashArvore -Raiz $raiz)
            $null = @(Invoke-Validacao -Raiz $raiz)
            $depois = @(Get-HashArvore -Raiz $raiz)

            ($depois -join "`n") | Should -BeExactly ($antes -join "`n") -Because $ctx

            $caminhosAntes = @($antes | ForEach-Object { ($_ -split '\|')[0] })
            $caminhosDepois = @($depois | ForEach-Object { ($_ -split '\|')[0] })
            @($caminhosDepois | Where-Object { $_ -notin $caminhosAntes }).Count | Should -Be 0 -Because "$ctx (arquivos criados)"
            @($caminhosAntes | Where-Object { $_ -notin $caminhosDepois }).Count | Should -Be 0 -Because "$ctx (arquivos removidos)"

            $gitAntes = @($antes | Where-Object { $_ -match '^[\\/]\.git[\\/]' })
            $gitDepois = @($depois | Where-Object { $_ -match '^[\\/]\.git[\\/]' })
            ($gitDepois -join "`n") | Should -BeExactly ($gitAntes -join "`n") -Because "$ctx (.git)"
            if ($comGit) { $gitDepois.Count | Should -BeGreaterThan 0 -Because $ctx }
        }
    }
}

Describe 'Property 12: Validação da frase de Tema' {

    # Feature: axios-segundo-cerebro, Property 12: Validação da frase de Tema
    # **Validates: Requirements 1.1, 1.4**

    BeforeAll {
        # Oráculo independente (regex): após aparar espaços/tabs das pontas, 1 a 300 caracteres,
        # sem \r/\n, terminando em um único ponto final (nenhum '.' imediatamente antes do último).
        function Get-EsperadoFraseTema {
            param([AllowEmptyString()][string]$Texto)
            $t = [regex]::Replace($Texto, '^[ \t]+|[ \t]+\z', '')
            return [regex]::IsMatch($t, '\A(?:[^\r\n]{0,298}[^.\r\n])?\.\z')
        }

        # Frase de $Len caracteres que termina em '.', sem espaço nas pontas e sem '.' antes do ponto final.
        function New-FraseTemaComTamanho {
            param([int]$Len)
            if ($Len -le 1) { return '.' }
            $letras = [char[]]'abcdefghijklmnopqrstuvwxyz0123456789'
            $meio = $letras + [char[]]@(' ', ' ', ',', ';', '.', [char]0x00E9, [char]0x00E7)
            $sb = [System.Text.StringBuilder]::new()
            for ($k = 0; $k -lt ($Len - 1); $k++) {
                $alfabeto = if ($k -eq 0 -or $k -eq ($Len - 2)) { $letras } else { $meio }
                [void]$sb.Append((Select-Aleatorio $alfabeto))
            }
            return $sb.ToString() + '.'
        }

        function Add-QuebraNoMeio {
            param([string]$Frase, [string]$Quebra)
            $pos = New-Inteiro -Min 1 -Max ($Frase.Length - 1)
            return $Frase.Insert($pos, $Quebra)
        }

        function New-Espacos {
            $n = New-Inteiro -Min 1 -Max 5
            return ((1..$n | ForEach-Object { Select-Aleatorio @(' ', "`t") }) -join '')
        }
    }

    It 'Test-FraseTema aceita exatamente 1 a 300 caracteres, sem quebra de linha, com um único ponto final (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 12'
        $casos = @('Valida', 'Tam1', 'Tam299', 'Tam300', 'Tam301', 'Longa', 'Vazia', 'SoEspacos', 'Padding', 'PaddingLongo',
            'QuebraLF', 'QuebraCR', 'QuebraCRLF', 'SemPonto', 'PontoDuplo', 'PontoTriplo')
        $esperadoPorCaso = @{
            Valida = $true; Tam1 = $true; Tam299 = $true; Tam300 = $true; Tam301 = $false; Longa = $false
            Vazia = $false; SoEspacos = $false; Padding = $true; PaddingLongo = $false
            QuebraLF = $false; QuebraCR = $false; QuebraCRLF = $false
            SemPonto = $false; PontoDuplo = $false; PontoTriplo = $false
        }
        Write-Host "Property 12: semente base $semente"

        for ($i = 0; $i -lt [Math]::Max($script:Iteracoes, 100); $i++) {
            # Os dois primeiros ciclos cobrem todos os casos, inclusive os limites 299/300/301.
            $caso = if ($i -lt $casos.Count) { $casos[$i] } else { Select-Aleatorio $casos }
            $ctx = "iteração $i, caso $caso, semente base $semente"

            $texto = switch ($caso) {
                'Valida' { New-FraseTemaComTamanho -Len (New-Inteiro -Min 1 -Max 300) }
                'Tam1' { '.' }
                'Tam299' { New-FraseTemaComTamanho -Len 299 }
                'Tam300' { New-FraseTemaComTamanho -Len 300 }
                'Tam301' { New-FraseTemaComTamanho -Len 301 }
                'Longa' { New-FraseTemaComTamanho -Len (New-Inteiro -Min 302 -Max 600) }
                'Vazia' { '' }
                'SoEspacos' { New-Espacos }
                'Padding' { (New-Espacos) + (New-FraseTemaComTamanho -Len (New-Inteiro -Min 1 -Max 300)) + (New-Espacos) }
                'PaddingLongo' { (New-Espacos) + (New-FraseTemaComTamanho -Len (New-Inteiro -Min 301 -Max 400)) + (New-Espacos) }
                'QuebraLF' { Add-QuebraNoMeio -Frase (New-FraseTemaComTamanho -Len (New-Inteiro -Min 2 -Max 299)) -Quebra "`n" }
                'QuebraCR' { Add-QuebraNoMeio -Frase (New-FraseTemaComTamanho -Len (New-Inteiro -Min 2 -Max 299)) -Quebra "`r" }
                'QuebraCRLF' { Add-QuebraNoMeio -Frase (New-FraseTemaComTamanho -Len (New-Inteiro -Min 2 -Max 298)) -Quebra "`r`n" }
                'SemPonto' { (New-FraseTemaComTamanho -Len (New-Inteiro -Min 2 -Max 300)).TrimEnd('.') }
                'PontoDuplo' { (New-FraseTemaComTamanho -Len (New-Inteiro -Min 2 -Max 299)) + '.' }
                'PontoTriplo' { (New-FraseTemaComTamanho -Len (New-Inteiro -Min 2 -Max 298)) + '..' }
            }

            $r = Test-FraseTema -Tema $texto
            $esperado = Get-EsperadoFraseTema -Texto $texto

            $esperado | Should -Be $esperadoPorCaso[$caso] -Because "$ctx (oráculo vs. intenção do caso)"
            $r.Valido | Should -Be $esperado -Because "$ctx (texto: [$texto])"
            if (-not $r.Valido) { [string]::IsNullOrWhiteSpace($r.Motivo) | Should -BeFalse -Because "$ctx (motivo vazio)" }
        }
    }

    It 'trata os limites 299/300/301 e entradas nula, vazia e só com espaços' {
        (Test-FraseTema -Tema (New-FraseTemaComTamanho -Len 299)).Valido | Should -BeTrue
        (Test-FraseTema -Tema (New-FraseTemaComTamanho -Len 300)).Valido | Should -BeTrue
        (Test-FraseTema -Tema (New-FraseTemaComTamanho -Len 301)).Valido | Should -BeFalse
        foreach ($t in @($null, '', '   ')) {
            $r = Test-FraseTema -Tema $t
            $r.Valido | Should -BeFalse
            $r.Motivo | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Property 15: Validação da Diretriz de Comportamento' {
    # Feature: axios-segundo-cerebro, Property 15: Validação da Diretriz de Comportamento
    # **Validates: Requirements 5.1, 5.2, 5.3, 5.4**

    BeforeAll {
        # Palavras com prefixo "x9" nunca formam "fonte", "final", "documento" nem "conhecimento externo".
        function New-PalavraNeutra { return ('x9' + (New-Palavra)) }
        function New-TemaNeutro {
            $n = New-Inteiro -Min 1 -Max 8
            return ((1..$n | ForEach-Object { New-PalavraNeutra }) -join ' ')
        }
        function New-InstrucaoPt {
            $pt = 'portugu' + [char]0x00EA + 's'
            return (Select-Aleatorio @("Responda sempre em $pt do Brasil.", "Use sempre o $pt do Brasil nas respostas."))
        }
        function New-InstrucaoFonte {
            return (Select-Aleatorio @(
                    'Indique a Fonte pelo nome do documento ao final de cada afirmacao.',
                    'Ao final de cada afirmacao, cite a fonte com o nome do documento.'))
        }
        function New-InstrucaoLimitacao {
            return (Select-Aleatorio @(
                    'Se o material nao tiver a informacao, declare a limitacao sem usar conhecimento externo.',
                    'Nunca use conhecimento externo; declare a limitacao quando faltar informacao.'))
        }
        function New-DiretrizTeste {
            # Monta a Diretriz com o prefixo e o Tema, as instruções pedidas e preenchimento até o tamanho-alvo.
            param(
                [string]$Prefixo,
                [string]$Tema,
                [string[]]$Instrucoes,
                [int]$Tamanho = 0
            )
            $partes = @($Instrucoes | Sort-Object { (Get-Rng).Next() })
            $base = ($Prefixo + $Tema + '. ' + ($partes -join ' ')).TrimEnd()
            if ($Tamanho -gt 0) {
                $falta = $Tamanho - $base.Length - 1
                if ($falta -lt 1) { throw "Tamanho-alvo $Tamanho menor que a base ($($base.Length))." }
                $base = $base + ' ' + ('a' * $falta)
            }
            elseif (New-Booleano) {
                $base = $base + ' ' + (New-Frase -MinPalavras 0 -MaxPalavras 40 | ForEach-Object { ($_ -split ' ' | ForEach-Object { "x9$_" }) -join ' ' })
                $base = $base.TrimEnd()
            }
            return $base
        }
        $script:PrefixoDiretriz = 'Comporte-se como um especialista em '
    }

    It 'Test-Diretriz aceita prefixo + Tema, até 4.000 caracteres e as três instruções, e rejeita qualquer violação (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 15'
        Write-Host "Property 15: semente base $semente"
        $casos = @('Valida', 'Lim3999', 'Lim4000', 'Lim4001', 'Longa',
            'FaltaPt', 'FaltaFonte', 'FaltaLimitacao', 'SoPrefixo',
            'PrefixoErrado', 'TemaDiferente', 'Vazia', 'SoEspacos')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $caso = if ($i -lt $casos.Count) { $casos[$i] } else { Select-Aleatorio $casos }
            $tema = New-TemaNeutro
            $todas = @((New-InstrucaoPt), (New-InstrucaoFonte), (New-InstrucaoLimitacao))
            $esperado = $false

            $texto = switch ($caso) {
                'Valida' { $esperado = $true; New-DiretrizTeste -Prefixo $script:PrefixoDiretriz -Tema $tema -Instrucoes $todas }
                'Lim3999' { $esperado = $true; New-DiretrizTeste -Prefixo $script:PrefixoDiretriz -Tema $tema -Instrucoes $todas -Tamanho 3999 }
                'Lim4000' { $esperado = $true; New-DiretrizTeste -Prefixo $script:PrefixoDiretriz -Tema $tema -Instrucoes $todas -Tamanho 4000 }
                'Lim4001' { New-DiretrizTeste -Prefixo $script:PrefixoDiretriz -Tema $tema -Instrucoes $todas -Tamanho 4001 }
                'Longa' { New-DiretrizTeste -Prefixo $script:PrefixoDiretriz -Tema $tema -Instrucoes $todas -Tamanho (New-Inteiro -Min 4002 -Max 6000) }
                'FaltaPt' { New-DiretrizTeste -Prefixo $script:PrefixoDiretriz -Tema $tema -Instrucoes @($todas[1], $todas[2]) }
                'FaltaFonte' { New-DiretrizTeste -Prefixo $script:PrefixoDiretriz -Tema $tema -Instrucoes @($todas[0], $todas[2]) }
                'FaltaLimitacao' { New-DiretrizTeste -Prefixo $script:PrefixoDiretriz -Tema $tema -Instrucoes @($todas[0], $todas[1]) }
                'SoPrefixo' { New-DiretrizTeste -Prefixo $script:PrefixoDiretriz -Tema $tema -Instrucoes @() }
                'PrefixoErrado' {
                    $errado = Select-Aleatorio @('Aja como um especialista em ', 'comporte-se como um especialista em ', 'Comporte-se como especialista em ', '')
                    New-DiretrizTeste -Prefixo $errado -Tema $tema -Instrucoes $todas
                }
                'TemaDiferente' { New-DiretrizTeste -Prefixo $script:PrefixoDiretriz -Tema ('y8' + $tema) -Instrucoes $todas }
                'Vazia' { Select-Aleatorio @('', $null) }
                'SoEspacos' { '   ' }
            }

            $tam = if ($null -eq $texto) { 0 } else { $texto.Length }
            $ctx = "iteração $i, caso $caso, semente base $semente, tamanho=$tam, tema='$tema'"
            if ($caso -eq 'Lim3999') { $tam | Should -Be 3999 -Because $ctx }
            if ($caso -eq 'Lim4000') { $tam | Should -Be 4000 -Because $ctx }
            if ($caso -eq 'Lim4001') { $tam | Should -Be 4001 -Because $ctx }

            $r = Test-Diretriz -Texto $texto -Tema $tema
            $r.Valido | Should -Be $esperado -Because $ctx
            if (-not $r.Valido) { [string]::IsNullOrWhiteSpace($r.Motivo) | Should -BeFalse -Because "$ctx (motivo vazio)" }
        }
    }
}

Describe 'Property 16: A Diretriz no README é idêntica ao arquivo' {

    # Feature: axios-segundo-cerebro, Property 16: A Diretriz no README é idêntica ao arquivo
    # **Validates: Requirements 5.5**
    # Convenção: o bloco extraído inclui a quebra de linha que antecede a cerca de fechamento.

    BeforeAll {
        function New-TextoDiretrizRoundTrip {
            # Texto T aleatório terminando em "`n", com Unicode, linhas em branco, acentos graves
            # isolados e sequências de 2 a 5 acentos graves.
            $unicode = @(Get-CaracteresUnicode) + @(Get-CaracteresEmoji)
            $sb = [System.Text.StringBuilder]::new()
            $nLinhas = New-Inteiro -Min 0 -Max 8
            for ($k = 0; $k -lt $nLinhas; $k++) {
                $nPedacos = New-Inteiro -Min 0 -Max 6
                for ($p = 0; $p -lt $nPedacos; $p++) {
                    switch (New-Inteiro -Min 0 -Max 4) {
                        0 { [void]$sb.Append((New-Frase -MinPalavras 1 -MaxPalavras 4)) }
                        1 { [void]$sb.Append((Select-Aleatorio $unicode)) }
                        2 { [void]$sb.Append('`') }
                        3 { [void]$sb.Append(('`' * (New-Inteiro -Min 2 -Max 5))) }
                        4 { [void]$sb.Append(' ') }
                    }
                }
                [void]$sb.Append("`n")   # inclui linhas em branco quando não há pedaços
            }
            [void]$sb.Append("`n")       # garante terminar em quebra de linha
            return $sb.ToString()
        }
        function Get-MaiorSequenciaAcentoGrave {
            param([string]$Texto)
            $m = [regex]::Matches($Texto, '`+') | ForEach-Object { $_.Length } | Measure-Object -Maximum
            if ($null -eq $m.Maximum) { return 0 }
            return [int]$m.Maximum
        }
        function New-SecaoVizinha {
            $t = "## " + (New-Frase -MinPalavras 1 -MaxPalavras 3)
            $corpo = New-Frase
            if (New-Booleano) { $corpo += "`n`n" + ('`' * 3) + "`ncodigo vizinho`n" + ('`' * 3) }
            return "$t`n`n$corpo`n`n"
        }
    }

    It 'Get-BlocoDiretriz devolve exatamente o texto embutido e $null sem seção ou sem fechamento (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 16'
        Write-Host "Property 16: semente base $semente"

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $t = New-TextoDiretrizRoundTrip
            $cerca = '`' * ((Get-MaiorSequenciaAcentoGrave -Texto $t) + (New-Inteiro -Min 1 -Max 3))
            if ($cerca.Length -lt 3) { $cerca = '`' * 3 }
            $titulo = if (New-Booleano) { '## Diretriz de comportamento' } else { '## ' + (New-Inteiro -Min 1 -Max 12) + '. Diretriz de comportamento' }
            $antes = (1..(New-Inteiro -Min 0 -Max 2) | ForEach-Object { New-SecaoVizinha }) -join ''
            $depois = (1..(New-Inteiro -Min 0 -Max 2) | ForEach-Object { New-SecaoVizinha }) -join ''
            $info = if (New-Booleano) { 'text' } else { '' }
            $ctx = "iteração $i, semente base $semente, cerca=$($cerca.Length), T.Length=$($t.Length)"

            $readme = "# Titulo`n`n" + $antes + "$titulo`n`nTexto introdutório.`n`n" + $cerca + $info + "`n" + $t + $cerca + "`n`n" + $depois
            $r = Get-BlocoDiretriz -TextoReadme $readme
            $r | Should -BeExactly $t -Because $ctx

            # Sem fechamento: $null.
            $semFecho = "# Titulo`n`n" + $antes + "$titulo`n`n" + $cerca + $info + "`n" + $t
            Get-BlocoDiretriz -TextoReadme $semFecho | Should -BeNullOrEmpty -Because "$ctx (sem fechamento)"

            # Sem a seção: $null (blocos de código só em seções vizinhas).
            $semSecao = "# Titulo`n`n" + $antes + "## Outra seção`n`n" + $cerca + "`n" + $t + $cerca + "`n`n" + $depois
            Get-BlocoDiretriz -TextoReadme $semSecao | Should -BeNullOrEmpty -Because "$ctx (sem seção)"
        }
    }

    It 'retorna $null para README vazio ou nulo e preserva a quebra de linha final do bloco' {
        Get-BlocoDiretriz -TextoReadme '' | Should -BeNullOrEmpty
        Get-BlocoDiretriz -TextoReadme $null | Should -BeNullOrEmpty
        $readme = "## Diretriz de comportamento`n`n" + ('`' * 3) + "`nlinha`n" + ('`' * 3) + "`n"
        Get-BlocoDiretriz -TextoReadme $readme | Should -BeExactly "linha`n"
    }
}

Describe 'Property 17: Status da Fonte' {

    # Feature: axios-segundo-cerebro, Property 17: Status da Fonte
    # **Validates: Requirements 4.4, 4.5, 4.6, 4.7**

    BeforeAll {
        $script:NomesCriterios = @('Autoria', 'Instituicao', 'DataPublicacao', 'Referencias', 'AcessoPublico')

        # Oráculo independente: aprovada <=> Autoria, AcessoPublico, >= 3 de 5, sem Dado Pessoal, com permissão e link acessível.
        function Get-EsperadoStatusFonte {
            param([bool[]]$C, [bool]$Dado, [bool]$Permitido, [bool]$Acessivel)
            $qtd = @($C | Where-Object { $_ }).Count
            if ($C[0] -and $C[4] -and $qtd -ge 3 -and -not $Dado -and $Permitido -and $Acessivel) { return 'aprovada' }
            return 'descartada'
        }

        function Test-StatusFonteTresFormas {
            param([bool[]]$C, [bool]$Dado, [bool]$Permitido, [bool]$Acessivel, [string]$Ctx)
            $esperado = Get-EsperadoStatusFonte -C $C -Dado $Dado -Permitido $Permitido -Acessivel $Acessivel

            $hash = @{}
            $obj = [ordered]@{}
            for ($k = 0; $k -lt 5; $k++) { $hash[$script:NomesCriterios[$k]] = $C[$k]; $obj[$script:NomesCriterios[$k]] = $C[$k] }
            $pso = [pscustomobject]$obj

            $r1 = Get-StatusFonte -Criterios ([object[]]$C) -DadoPessoal $Dado -CompartilhamentoPermitido $Permitido -LinkAcessivel $Acessivel
            $r2 = Get-StatusFonte -Criterios $hash -DadoPessoal $Dado -CompartilhamentoPermitido $Permitido -LinkAcessivel $Acessivel
            $r3 = Get-StatusFonte -Criterios $pso -DadoPessoal $Dado -CompartilhamentoPermitido $Permitido -LinkAcessivel $Acessivel
            $r1 | Should -BeExactly $esperado -Because "$Ctx (array)"
            $r2 | Should -BeExactly $esperado -Because "$Ctx (hashtable)"
            $r3 | Should -BeExactly $esperado -Because "$Ctx (objeto)"
        }
    }

    It 'cobre exaustivamente as 32 combinações dos cinco critérios com todas as combinações de Dado Pessoal, permissão e link' {
        for ($m = 0; $m -lt 32; $m++) {
            $c = [bool[]]@(0..4 | ForEach-Object { [bool](($m -shr $_) -band 1) })
            foreach ($dado in $false, $true) {
                foreach ($perm in $false, $true) {
                    foreach ($link in $false, $true) {
                        Test-StatusFonteTresFormas -C $c -Dado $dado -Permitido $perm -Acessivel $link -Ctx "máscara $m, dado $dado, permissão $perm, link $link"
                    }
                }
            }
        }
    }

    It 'retorna aprovada se e somente se as condições valem (>= 100 iterações aleatórias)' {
        $semente = Initialize-Gerador -Contexto 'Property 17'
        Write-Host "Property 17: semente base $semente"

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $c = [bool[]]@(0..4 | ForEach-Object { New-Booleano })
            $dado = New-Booleano; $perm = New-Booleano; $link = New-Booleano
            Test-StatusFonteTresFormas -C $c -Dado $dado -Permitido $perm -Acessivel $link -Ctx "iteração $i, semente base $semente"
        }
    }

    It 'exemplos: aprova com Autoria, Acesso Público e um terceiro critério; descarta sem Autoria, com Dado Pessoal ou com apenas 2 critérios' {
        Get-StatusFonte -Criterios @($true, $true, $false, $false, $true) | Should -BeExactly 'aprovada'
        Get-StatusFonte -Criterios @($true, $false, $false, $false, $true) | Should -BeExactly 'descartada'
        Get-StatusFonte -Criterios @($false, $true, $true, $true, $true) | Should -BeExactly 'descartada'
        Get-StatusFonte -Criterios @($true, $true, $true, $true, $true) -DadoPessoal $true | Should -BeExactly 'descartada'
        Get-StatusFonte -Criterios @{ Autoria = $true; Instituicao = $true; AcessoPublico = $true } -LinkAcessivel $false | Should -BeExactly 'descartada'
    }
}

Describe 'Property 18: Contagem de perguntas válidas' {

    # Feature: axios-segundo-cerebro, Property 18: Contagem de perguntas válidas
    # **Validates: Requirements 7.2, 7.3, 7.4, 7.6, 7.7**

    It 'Measure-PerguntasValidas conta exatamente as linhas com Fonte citada e Print de Chat que resolve para imagem existente (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 18'
        Write-Host "Property 18: semente base $semente"

        $casos = @('Valida', 'Valida', 'SemFonteVazia', 'SemCitacao', 'PrintInexistente', 'PrintNaoImagem', 'PrintSoTexto')
        $extImagem = @('png', 'jpg', 'jpeg', 'gif', 'webp')

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $ctx = "iteração $i, semente base $semente"
            $raiz = Join-Path $TestDrive "p18-$i"
            $dirPrints = Join-Path $raiz 'materiais/prints-chat'
            New-Item -ItemType Directory -Path $dirPrints -Force | Out-Null

            $linhas = New-Object System.Collections.Generic.List[string]
            if (New-Booleano) { $linhas.Add('| nº | pergunta | resposta resumida | Fontes citadas | Print de Chat |') }
            if (New-Booleano) { $linhas.Add('|---|---|---|---|---|') }

            $n = New-Inteiro -Min 0 -Max 15
            $esperado = 0
            for ($k = 1; $k -le $n; $k++) {
                $caso = Select-Aleatorio -Itens $casos
                $qtdFontes = New-Inteiro -Min 1 -Max 5
                $fontes = (1..$qtdFontes | ForEach-Object { "doc-$(New-Palavra -Min 2 -Max 8).pdf" }) -join ', '
                $nome = "print-$k-$(New-Palavra -Min 3 -Max 8)"
                $print = ''

                switch ($caso) {
                    'Valida' {
                        $arq = "$nome.$(Select-Aleatorio -Itens $extImagem)"
                        Set-Content -LiteralPath (Join-Path $dirPrints $arq) -Value 'img'
                        $print = "[captura](materiais/prints-chat/$arq)"
                        $esperado++
                    }
                    'SemFonteVazia' {
                        $fontes = ''
                        $arq = "$nome.png"
                        Set-Content -LiteralPath (Join-Path $dirPrints $arq) -Value 'img'
                        $print = "[captura](materiais/prints-chat/$arq)"
                    }
                    'SemCitacao' {
                        $fontes = 'sem citação'
                        $arq = "$nome.png"
                        Set-Content -LiteralPath (Join-Path $dirPrints $arq) -Value 'img'
                        $print = "[captura](materiais/prints-chat/$arq)"
                    }
                    'PrintInexistente' {
                        $print = "[captura](materiais/prints-chat/$nome.png)"
                    }
                    'PrintNaoImagem' {
                        $arq = "$nome.$(Select-Aleatorio -Itens @('txt', 'pdf', 'md'))"
                        Set-Content -LiteralPath (Join-Path $dirPrints $arq) -Value 'texto'
                        $print = "[captura](materiais/prints-chat/$arq)"
                    }
                    'PrintSoTexto' {
                        $print = "captura $(New-Palavra -Min 3 -Max 8)"
                    }
                }
                $linhas.Add("| $k | pergunta $k | resposta $k | $fontes | $print |")
            }

            $obtido = Measure-PerguntasValidas -Linhas $linhas.ToArray() -Raiz $raiz
            $obtido | Should -Be $esperado -Because "$ctx; linhas: $($linhas -join ' // ')"
        }
    }

    It 'exemplos: sem linhas vale 0; cabeçalho e separador não contam' {
        $raiz = Join-Path $TestDrive 'p18-ex'
        New-Item -ItemType Directory -Path $raiz -Force | Out-Null
        Measure-PerguntasValidas -Linhas @() -Raiz $raiz | Should -Be 0
        Measure-PerguntasValidas -Linhas @('| nº | pergunta | resposta resumida | Fontes citadas | Print de Chat |', '|---|---|---|---|---|') -Raiz $raiz | Should -Be 0
    }
}

Describe 'Property 19: Normalização do remoto origin' {

    # Feature: axios-segundo-cerebro, Property 19: Normalização do remoto origin
    # **Validates: Requirements 11.1, 11.3**

    BeforeAll {
        function script:Set-CaixaAleatoriaLocal {
            param([string]$Texto)
            $sb = New-Object System.Text.StringBuilder
            foreach ($c in $Texto.ToCharArray()) {
                if (New-Booleano) { [void]$sb.Append([char]::ToUpperInvariant($c)) } else { [void]$sb.Append([char]::ToLowerInvariant($c)) }
            }
            return $sb.ToString()
        }
    }

    It 'Test-RemoteOrigin é verdadeiro só para o URL esperado normalizado (>= 100 iterações)' {
        $semente = Initialize-Gerador -Contexto 'Property 19'
        Write-Host "Property 19: semente base $semente"

        $esperado = 'https://github.com/Gtvnv/axios-segundo-cerebro'

        for ($i = 0; $i -lt $script:Iteracoes; $i++) {
            $ctx = "iteração $i, semente base $semente"

            # Positivos: caixa aleatória, .git e barras finais opcionais.
            $url = script:Set-CaixaAleatoriaLocal -Texto $esperado
            if (New-Booleano) { $url += '/' * (New-Inteiro -Min 1 -Max 3) }
            if (New-Booleano) { $url += (script:Set-CaixaAleatoriaLocal -Texto '.git') }
            if (New-Booleano) { $url += '/' * (New-Inteiro -Min 1 -Max 3) }
            (Test-RemoteOrigin -Url $url) | Should -BeTrue -Because "positivo '$url' ($ctx)"

            # Negativos: um tipo por iteração.
            $tipo = Select-Aleatorio -Itens @('OutraConta', 'OutroRepo', 'Http', 'Ssh', 'GitAt', 'CaminhoExtra', 'Vazio', 'Aleatoria', 'Prefixo', 'Sufixo', 'HostParecido')
            $p1 = New-Palavra -Min 2 -Max 8
            $neg = switch ($tipo) {
                'OutraConta'   { "https://github.com/$p1/axios-segundo-cerebro" }
                'OutroRepo'    { "https://github.com/Gtvnv/$p1" }
                'Http'         { 'http://github.com/Gtvnv/axios-segundo-cerebro' }
                'Ssh'          { Select-Aleatorio -Itens @('ssh://git@github.com/Gtvnv/axios-segundo-cerebro.git', 'ssh://github.com/Gtvnv/axios-segundo-cerebro') }
                'GitAt'        { 'git@github.com:Gtvnv/axios-segundo-cerebro.git' }
                'CaminhoExtra' { Select-Aleatorio -Itens @("$esperado/$p1", "$esperado.git/$p1", "https://github.com/$p1/Gtvnv/axios-segundo-cerebro", "$esperado/tree/main") }
                'Vazio'        { Select-Aleatorio -Itens @($null, '', (' ' * (New-Inteiro -Min 1 -Max 5)), "`t", "  `r`n ") }
                'Aleatoria'    { "$(Select-Aleatorio -Itens @('https', 'http', 'ftp'))://$(New-Palavra -Min 2 -Max 8).com/$(New-Palavra -Min 2 -Max 8)/$(New-Palavra -Min 2 -Max 8)" }
                'Prefixo'      { "x$esperado" }
                'Sufixo'       { Select-Aleatorio -Itens @("$esperado-x", "${esperado}2", "$esperado.gitx", "$esperado.git.git", "$esperado.$p1") }
                'HostParecido' { Select-Aleatorio -Itens @('https://github.com.evil.io/Gtvnv/axios-segundo-cerebro', 'https://gitlab.com/Gtvnv/axios-segundo-cerebro', 'https://www.github.com/Gtvnv/axios-segundo-cerebro') }
            }
            if ($tipo -in @('OutraConta', 'OutroRepo', 'Http', 'CaminhoExtra', 'Prefixo', 'Sufixo', 'HostParecido') -and (New-Booleano)) {
                $neg = script:Set-CaixaAleatoriaLocal -Texto $neg
            }
            if ($tipo -in @('OutraConta', 'OutroRepo') -and $neg -ieq $esperado) { continue }
            (Test-RemoteOrigin -Url $neg) | Should -BeFalse -Because "negativo ($tipo) '$neg' ($ctx)"
        }
    }

    It 'exemplos fixos' {
        Test-RemoteOrigin -Url 'https://github.com/Gtvnv/axios-segundo-cerebro.git/' | Should -BeTrue
        Test-RemoteOrigin -Url 'HTTPS://GITHUB.COM/GTVNV/AXIOS-SEGUNDO-CEREBRO' | Should -BeTrue
        Test-RemoteOrigin -Url $null | Should -BeFalse
        Test-RemoteOrigin -Url '' | Should -BeFalse
        Test-RemoteOrigin -Url '   ' | Should -BeFalse
    }
}
