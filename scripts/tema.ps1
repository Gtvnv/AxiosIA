# Apoio de Tema e Evolucoes do AXIOS.
# Pode ser carregado por dot-sourcing (. ./scripts/tema.ps1); este arquivo so define funcoes.

function ConvertTo-ConteudoNovo {
    <#
    .SYNOPSIS
        Funcao pura: calcula o novo conteudo de um arquivo na troca ou confirmacao do Tema.
    .DESCRIPTION
        Substitui todas as ocorrencias literais (ordinais, com diferenciacao de maiusculas)
        de TemaAntigo por TemaNovo. Com -Confirmar, remove tambem o marcador "(proposto)"
        e os espacos que o precedem na mesma linha. Nao le nem grava disco.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Texto,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TemaAntigo,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TemaNovo,
        [switch]$Confirmar
    )

    $resultado = $Texto
    if ($TemaAntigo.Length -gt 0 -and $TemaAntigo -cne $TemaNovo) {
        $resultado = $resultado.Replace($TemaAntigo, $TemaNovo)
    }
    if ($Confirmar) {
        $resultado = [regex]::Replace($resultado, '[ \t]*\(proposto\)', '')
    }
    return $resultado
}

function Set-ArquivosAtomico {
    <#
    .SYNOPSIS
        Grava varios arquivos em duas fases, de modo que o resultado seja "tudo novo" ou "tudo antigo".
    .DESCRIPTION
        Itens: lista de objetos ou hashtables com as propriedades Caminho e Conteudo.
        Fase 1: grava cada conteudo em <arquivo>.axios-novo (nenhum original e alterado).
        Fase 2: para cada arquivo, copia o original para <arquivo>.axios-bak e move o temporario
                sobre o original.
        Em falha na fase 1, apaga os temporarios. Em falha na fase 2, restaura todos os originais
        a partir dos .axios-bak e apaga temporarios e backups. Em sucesso, apaga os .axios-bak.

        -FalhaInjetada: bloco opcional usado nos testes. E chamado com dois argumentos,
        (Fase, Caminho), imediatamente antes de cada operacao (Fase 1: gravar o temporario;
        Fase 2: copiar o backup e mover o temporario). Se lancar excecao ou retornar $true,
        a operacao e tratada como falha naquele arquivo.

        Retorna objeto com: Sucesso, ArquivoCausador, Fase, Mensagem, FalhaNaReversao,
        BackupsParaRestauracao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Itens,
        [scriptblock]$FalhaInjetada
    )

    $resolver = { param($p) $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p) }
    $utf8 = New-Object System.Text.UTF8Encoding($false)

    $lista = @()
    foreach ($item in $Itens) {
        $real = & $resolver ([string]$item.Caminho)
        $lista += [pscustomobject]@{
            Caminho   = [string]$item.Caminho
            Real      = $real
            Novo      = "$real.axios-novo"
            Bak       = "$real.axios-bak"
            Conteudo  = [string]$item.Conteudo
            Existia   = (Test-Path -LiteralPath $real -PathType Leaf)
            BakFeito  = $false
            Trocado   = $false
        }
    }

    $resultado = {
        param($ok, $causador, $fase, $msg, $falhaRev, $baks)
        [pscustomobject]@{
            Sucesso                = $ok
            ArquivoCausador        = $causador
            Fase                   = $fase
            Mensagem               = $msg
            FalhaNaReversao        = $falhaRev
            BackupsParaRestauracao = @($baks)
        }
    }

    $injetar = {
        param($fase, $caminho)
        if ($null -ne $FalhaInjetada) {
            $r = & $FalhaInjetada $fase $caminho
            if ($r -is [bool] -and $r) { throw "Falha injetada na fase $fase em '$caminho'." }
        }
    }

    $apagar = {
        param($caminhos)
        foreach ($c in $caminhos) {
            Remove-Item -LiteralPath $c -Force -ErrorAction SilentlyContinue
        }
    }

    # Fase 1: gravar temporarios
    foreach ($a in $lista) {
        try {
            & $injetar 1 $a.Caminho
            [System.IO.File]::WriteAllText($a.Novo, $a.Conteudo, $utf8)
        }
        catch {
            & $apagar ($lista | ForEach-Object { $_.Novo })
            return (& $resultado $false $a.Caminho 1 $_.Exception.Message $false @())
        }
    }

    # Fase 2: backup e troca
    $causador = $null
    $erro = $null
    foreach ($a in $lista) {
        try {
            & $injetar 2 $a.Caminho
            if ($a.Existia) {
                Copy-Item -LiteralPath $a.Real -Destination $a.Bak -Force -ErrorAction Stop
            }
            $a.BakFeito = $true
            Move-Item -LiteralPath $a.Novo -Destination $a.Real -Force -ErrorAction Stop
            $a.Trocado = $true
        }
        catch {
            $causador = $a.Caminho
            $erro = $_.Exception.Message
            break
        }
    }

    if ($null -eq $causador) {
        & $apagar ($lista | ForEach-Object { $_.Bak })
        return (& $resultado $true $null 2 'Todos os arquivos foram atualizados.' $false @())
    }

    # Reversao
    $pendentes = @()
    foreach ($a in $lista) {
        try {
            if ($a.Existia) {
                if ($a.BakFeito -and (Test-Path -LiteralPath $a.Bak -PathType Leaf)) {
                    Copy-Item -LiteralPath $a.Bak -Destination $a.Real -Force -ErrorAction Stop
                }
            }
            elseif ($a.Trocado) {
                Remove-Item -LiteralPath $a.Real -Force -ErrorAction Stop
            }
        }
        catch {
            $pendentes += $a.Bak
        }
    }
    & $apagar ($lista | ForEach-Object { $_.Novo })
    if ($pendentes.Count -eq 0) {
        & $apagar ($lista | ForEach-Object { $_.Bak })
        return (& $resultado $false $causador 2 $erro $false @())
    }
    # Preserva apenas os .axios-bak necessarios para restauracao manual
    $manter = $lista | Where-Object { $pendentes -contains $_.Bak }
    & $apagar ($lista | Where-Object { $manter -notcontains $_ } | ForEach-Object { $_.Bak })
    return (& $resultado $false $causador 2 $erro $true $pendentes)
}

function Set-Tema {
    <#
    .SYNOPSIS
        Troca o Tema (e opcionalmente o Objetivo) e/ou confirma o Tema removendo "(proposto)".
    .DESCRIPTION
        Valida o Tema com Test-FraseTema (de scripts/validar.ps1, carregado por dot-source so se
        ainda nao existir). Entrada invalida: nada e gravado e o Motivo e retornado.
        O Tema vigente e lido de docs/diretriz-de-comportamento.md (primeira frase, apos o prefixo
        "Comporte-se como um especialista em "). Os arquivos README.md e docs/*.md que citam o Tema
        (ou, com -Confirmar, o marcador) sao atualizados por Set-ArquivosAtomico.
        Retorna: Sucesso, Motivo, ArquivoCausador, ArquivosAlterados.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Raiz,
        [AllowNull()][AllowEmptyString()][string]$Tema,
        [AllowNull()][AllowEmptyString()][string]$Objetivo,
        [switch]$Confirmar,
        [scriptblock]$FalhaInjetada
    )

    $res = {
        param($ok, $motivo, $causador, $alterados)
        [pscustomobject]@{
            Sucesso           = $ok
            Motivo            = $motivo
            ArquivoCausador   = $causador
            ArquivosAlterados = @($alterados)
        }
    }

    if (-not (Get-Command Test-FraseTema -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'validar.ps1')
    }

    $temTema = $PSBoundParameters.ContainsKey('Tema')
    $temObjetivo = $PSBoundParameters.ContainsKey('Objetivo')
    if (-not $temTema -and -not $temObjetivo -and -not $Confirmar) {
        return (& $res $false 'Nada a fazer: informe Tema, Objetivo ou -Confirmar.' $null @())
    }

    $novoTema = $null
    if ($temTema) {
        $v = Test-FraseTema -Tema $Tema
        if (-not $v.Valido) { return (& $res $false $v.Motivo $null @()) }
        $novoTema = $Tema.Trim().TrimEnd('.')
    }
    if ($temObjetivo -and ([string]::IsNullOrWhiteSpace($Objetivo) -or $Objetivo -match '[\r\n]')) {
        return (& $res $false 'Objetivo vazio ou com quebra de linha.' $null @())
    }

    $diretriz = Join-Path $Raiz 'docs/diretriz-de-comportamento.md'
    $candidatos = @(Join-Path $Raiz 'README.md')
    $docs = Join-Path $Raiz 'docs'
    if (Test-Path -LiteralPath $docs -PathType Container) {
        $candidatos += @(Get-ChildItem -LiteralPath $docs -Filter '*.md' -File | Sort-Object Name | ForEach-Object { $_.FullName })
    }

    # Leitura de todos os arquivos afetados
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $textos = [ordered]@{}
    foreach ($c in $candidatos) {
        try { $textos[$c] = [System.IO.File]::ReadAllText($c, $utf8) }
        catch { return (& $res $false "Falha ao ler o arquivo: $($_.Exception.Message)" $c @()) }
    }

    $antigo = ''
    $prefixo = 'Comporte-se como um especialista em '
    if (Test-Path -LiteralPath $diretriz -PathType Leaf) {
        $textoDiretriz = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $diretriz).Path, $utf8)
        $m = [regex]::Match($textoDiretriz, '^' + [regex]::Escape($prefixo) + '(?<t>[^\r\n]*?)\.(?=\s|$)')
        if ($m.Success) { $antigo = $m.Groups['t'].Value }
    }
    if ($temTema -and $antigo -eq '') {
        return (& $res $false 'Tema vigente nao encontrado em docs/diretriz-de-comportamento.md.' $diretriz @())
    }
    if (-not $temTema) { $novoTema = $antigo }

    $itens = @()
    foreach ($c in $candidatos) {
        $texto = $textos[$c]
        $novo = ConvertTo-ConteudoNovo -Texto $texto -TemaAntigo $antigo -TemaNovo $novoTema -Confirmar:$Confirmar
        if ($temObjetivo -and (Split-Path -Leaf $c) -ceq 'README.md') {
            $obj = $Objetivo.Trim().TrimEnd('.')
            $novo = [regex]::Replace($novo, '(?m)^(Tema: .*?, com o objetivo de ).*?((?: \(proposto\))?\.)[ \t]*$', {
                    param($mm) $mm.Groups[1].Value + $obj + $mm.Groups[2].Value
                })
        }
        if ($novo -cne $texto) { $itens += [pscustomobject]@{ Caminho = $c; Conteudo = $novo } }
    }

    if ($itens.Count -eq 0) { return (& $res $true '' $null @()) }

    $r = Set-ArquivosAtomico -Itens $itens -FalhaInjetada $FalhaInjetada
    if ($r.Sucesso) {
        return (& $res $true '' $null @($itens | ForEach-Object { $_.Caminho }))
    }
    $motivo = "Falha na fase $($r.Fase): $($r.Mensagem)"
    if ($r.FalhaNaReversao) {
        $motivo += ' Reversao incompleta; restaure manualmente a partir de: ' + ($r.BackupsParaRestauracao -join ', ')
    }
    return (& $res $false $motivo $r.ArquivoCausador @())
}

function Get-EvolucoesDisponiveis {
    <#
    .SYNOPSIS
        Le docs/evolucoes.md e retorna as ideias como objetos { Titulo, Descricao } (secoes "## ").
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Raiz)

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $caminho = Join-Path $Raiz 'docs/evolucoes.md'
    $texto = [System.IO.File]::ReadAllText($caminho, $utf8)
    $lista = @()
    $titulo = $null
    $corpo = @()
    foreach ($linha in ($texto -split "\r?\n")) {
        if ($linha -match '^##\s+(.+?)\s*$' -and $linha -notmatch '^###') {
            if ($null -ne $titulo) { $lista += [pscustomobject]@{ Titulo = $titulo; Descricao = (($corpo -join ' ').Trim()) } }
            $titulo = $Matches[1]
            $corpo = @()
        }
        elseif ($null -ne $titulo -and $linha.Trim().Length -gt 0) {
            $corpo += $linha.Trim()
        }
    }
    if ($null -ne $titulo) { $lista += [pscustomobject]@{ Titulo = $titulo; Descricao = (($corpo -join ' ').Trim()) } }
    return @($lista)
}

function Add-Evolucoes {
    <#
    .SYNOPSIS
        Acrescenta ao README, na secao "Evolucoes", as evolucoes opcionais pedidas pelo Usuario.
    .DESCRIPTION
        Nomes: de 1 a 4 titulos, exatamente como em docs/evolucoes.md. Pedido com 0 ou mais de 4
        itens, ou com qualquer nome desconhecido, e rejeitado por inteiro (nada e gravado) e o Motivo
        informa o problema e as quatro opcoes validas. Para cada evolucao nova, uma linha
        "- **Titulo**: descricao" (1 a 3 frases, copiada de docs/evolucoes.md) e acrescentada na
        secao "## Evolucoes" (criada ao final do README se nao existir), sem tocar nas demais secoes.
        Req. 12.3: para cada evolucao sem subsecao "## Titulo" em docs/roteiro-manual.md, acrescenta
        ao final do roteiro essa subsecao com 10 passos numerados (1 a 10), preservando o conteudo
        anterior (os nove passos do roteiro ficam intactos). Evolucoes com subsecao no roteiro sao
        "ja existentes" (Req. 12.5/12.6) e nao sao duplicadas. README e roteiro sao gravados juntos
        por Set-ArquivosAtomico (somente os que mudam).
        Retorna: Sucesso, Motivo, Adicionadas, JaExistentes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Raiz,
        # AllowEmptyString: um elemento '' deve chegar ao corpo e ser rejeitado com Motivo (Req. 12.4),
        # em vez de gerar ParameterBindingValidationException.
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowNull()][AllowEmptyString()][string[]]$Nomes,
        [scriptblock]$FalhaInjetada
    )

    if (-not (Get-Command Find-Placeholders -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'validar.ps1')
    }

    $res = {
        param($ok, $motivo, $adicionadas, $existentes)
        [pscustomobject]@{
            Sucesso      = $ok
            Motivo       = $motivo
            Adicionadas  = @($adicionadas)
            JaExistentes = @($existentes)
        }
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $arqEvo = Join-Path $Raiz 'docs/evolucoes.md'
    $arqReadme = Join-Path $Raiz 'README.md'
    $arqRoteiro = Join-Path $Raiz 'docs/roteiro-manual.md'
    try {
        $disponiveis = @(Get-EvolucoesDisponiveis -Raiz $Raiz)
        $readme = [System.IO.File]::ReadAllText($arqReadme, $utf8)
        $roteiro = [System.IO.File]::ReadAllText($arqRoteiro, $utf8)
    }
    catch {
        return (& $res $false "Falha ao ler os arquivos: $($_.Exception.Message)" @() @())
    }
    if ($disponiveis.Count -eq 0) {
        return (& $res $false 'Nenhuma evolucao encontrada em docs/evolucoes.md.' @() @())
    }
    $opcoes = ($disponiveis | ForEach-Object { '"' + $_.Titulo + '"' }) -join ', '

    $pedidos = @($Nomes | Where-Object { $null -ne $_ })
    if ($pedidos.Count -lt 1 -or $pedidos.Count -gt 4) {
        return (& $res $false "Solicitacao com $($pedidos.Count) itens; informe de 1 a 4 evolucoes. Opcoes validas: $opcoes." @() @())
    }
    $desconhecidas = @($pedidos | Where-Object { $n = $_; -not ($disponiveis | Where-Object { $_.Titulo -ceq $n }) })
    if ($desconhecidas.Count -gt 0) {
        $lista = ($desconhecidas | ForEach-Object { '"' + $_ + '"' }) -join ', '
        return (& $res $false "Evolucoes inexistentes: $lista. Opcoes validas: $opcoes. Nada foi alterado." @() @())
    }

    $nl = if ($readme.Contains("`r`n")) { "`r`n" } else { "`n" }
    $linhas = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($readme -split "\r?\n")) { $linhas.Add($l) }

    # Localiza a secao "Evolucoes" (titulo sem numeracao inicial).
    $ini = -1
    for ($i = 0; $i -lt $linhas.Count; $i++) {
        if ($linhas[$i] -match '^##\s+(?:\d+[.)]\s+)?Evolu(ç|c)(õ|o)es\s*$') { $ini = $i; break }
    }
    $fim = $linhas.Count
    if ($ini -ge 0) {
        for ($j = $ini + 1; $j -lt $linhas.Count; $j++) {
            if ($linhas[$j] -match '^#{1,6}\s') { $fim = $j; break }
        }
    }
    $corpoSecao = if ($ini -ge 0) { ($linhas.GetRange($ini, $fim - $ini) -join "`n") } else { '' }

    # Uma evolucao "ja existe" (Req. 12.5/12.6) quando tem subsecao "## Titulo" no roteiro.
    # O README e completado a parte, sem duplicar, caso falte a linha da evolucao na secao.
    $linhasRoteiro = @($roteiro -split "\r?\n")
    $novas = @()          # sem subsecao no roteiro
    $existentes = @()     # com subsecao no roteiro
    $paraReadme = @()     # sem linha na secao Evolucoes do README
    foreach ($n in ($pedidos | Select-Object -Unique)) {
        $d = $disponiveis | Where-Object { $_.Titulo -ceq $n } | Select-Object -First 1
        if ($linhasRoteiro -ccontains ('## ' + $d.Titulo)) { $existentes += $d.Titulo }
        else { $novas += $d }
        if (-not $corpoSecao.Contains('**' + $d.Titulo + '**')) { $paraReadme += $d }
    }

    if ($novas.Count -eq 0 -and $paraReadme.Count -eq 0) {
        return (& $res $true 'As evolucoes solicitadas ja foram adicionadas; nada foi alterado.' @() $existentes)
    }

    $itensNovos = @($paraReadme | ForEach-Object { '- **' + $_.Titulo + '**: ' + $_.Descricao })

    # Subsecao do roteiro: titulo da evolucao e 10 passos numerados (1 a 10), um por linha.
    $blocosRoteiro = @()
    foreach ($d in $novas) {
        $t = $d.Titulo
        $passos = @(
            "Releia a descrição da evolução ""$t"" em ``docs/evolucoes.md`` e escreva em uma frase o resultado esperado.",
            "Confirme que o Notebook já tem Fontes aprovadas em ``docs/registro-de-fontes.md`` e que os nove passos do roteiro estão concluídos.",
            "Defina o que muda nas Fontes ou nos pedidos ao Notebook para esta evolução, seguindo a ideia: $($d.Descricao)",
            "Faça a mudança no Notebook e registre, em ``docs/registro-de-fontes.md``, qualquer Fonte nova com número, título, formato, link, autoria, data, status e motivo.",
            "Faça de 1 a 3 perguntas ao Notebook para testar o resultado e confira cada citação no trecho original da Fonte.",
            "Registre pergunta, resposta resumida, Fontes citadas e link relativo do Print de Chat em ``docs/registro-de-perguntas.md``.",
            "Salve o material gerado na pasta de ``materiais/`` do seu tipo, com nome só em letras minúsculas, dígitos e hífens, e liste o nome no README dessa pasta.",
            "Remova Dado Pessoal dos arquivos e confirme a permissão de compartilhamento de cada Fonte nova.",
            "Confirme que a evolução consta na seção ""Evoluções"" do ``README.md`` com o título ""$t"".",
            "Execute ``scripts/validar.ps1`` e corrija qualquer FALHA antes de publicar de novo o Repositório."
        )
        $b = @('', "## $t", '')
        for ($k = 0; $k -lt $passos.Count; $k++) { $b += ('{0}. {1}' -f ($k + 1), $passos[$k]) }
        $blocosRoteiro += , $b
    }
    $textoNovoRoteiro = ($blocosRoteiro | ForEach-Object { $_ -join "`n" }) -join "`n"

    $achados = @(Find-Placeholders -Texto (($itensNovos -join "`n") + "`n" + $textoNovoRoteiro) | ForEach-Object { $_ } | Where-Object { $_ -is [string] -and $_.Length -gt 0 })
    if ($achados.Count -gt 0) {
        return (& $res $false 'Descricao de evolucao contem Termo_de_Placeholder; nada foi alterado.' @() $existentes)
    }

    $novoRoteiro = $null
    if ($novas.Count -gt 0) {
        $baseRot = $roteiro.TrimEnd("`r", "`n")
        $nlRot = if ($roteiro.Contains("`r`n")) { "`r`n" } else { "`n" }
        $novoRoteiro = $baseRot + $nlRot + ($textoNovoRoteiro -replace "`n", $nlRot) + $nlRot
    }

    if ($itensNovos.Count -eq 0) {
        # README ja contem todas as linhas; nada a inserir.
    }
    elseif ($ini -ge 0) {
        # Insere apos a ultima linha nao vazia da secao.
        $pos = $fim
        while ($pos -gt $ini + 1 -and $linhas[$pos - 1].Trim().Length -eq 0) { $pos-- }
        $linhas.InsertRange($pos, [string[]]$itensNovos)
        if ($ini + 1 -eq $pos) { $linhas.Insert($ini + 1, '') ; }
    }
    else {
        while ($linhas.Count -gt 0 -and $linhas[$linhas.Count - 1].Trim().Length -eq 0) { $linhas.RemoveAt($linhas.Count - 1) }
        $linhas.Add('')
        $linhas.Add('## Evoluções')
        $linhas.Add('')
        foreach ($it in $itensNovos) { $linhas.Add($it) }
        $linhas.Add('')
    }
    $novoReadme = ($linhas -join $nl)

    # Grava README e roteiro de forma atomica (somente os que mudaram).
    $itensGravar = @()
    if ($itensNovos.Count -gt 0) { $itensGravar += [pscustomobject]@{ Caminho = $arqReadme; Conteudo = $novoReadme } }
    if ($null -ne $novoRoteiro) { $itensGravar += [pscustomobject]@{ Caminho = $arqRoteiro; Conteudo = $novoRoteiro } }
    $r = Set-ArquivosAtomico -Itens $itensGravar -FalhaInjetada $FalhaInjetada
    if ($r.Sucesso) {
        return (& $res $true '' @($novas | ForEach-Object { $_.Titulo }) $existentes)
    }
    $motivo = "Falha na fase $($r.Fase): $($r.Mensagem)"
    if ($r.FalhaNaReversao) {
        $motivo += ' Reversao incompleta; restaure manualmente a partir de: ' + ($r.BackupsParaRestauracao -join ', ')
    }
    return (& $res $false $motivo @() $existentes)
}
