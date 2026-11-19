<#
.SYNOPSIS
    Validador do repositório axios-segundo-cerebro.

.DESCRIPTION
    Pode ser carregado por dot-sourcing (. ./scripts/validar.ps1) para importar
    as funções sem executar a validação. Executado diretamente, roda a validação
    completa quando Invoke-Validacao estiver definida.

.PARAMETER Raiz
    Raiz do repositório. Padrão: pasta pai de scripts/.
#>
[CmdletBinding()]
param(
    [string]$Raiz = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest

# Remove âncora e consulta e decodifica %20 de um destino de link.
function ConvertTo-DestinoLimpo {
    param([string]$Destino)
    $d = $Destino
    $i = $d.IndexOfAny([char[]]@('#', '?'))
    if ($i -ge 0) { $d = $d.Substring(0, $i) }
    return ($d -replace '%20', ' ')
}

# Destinos de [texto](destino) que não começam com http://, https:// ou #.
function Get-LinksRelativos {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Texto)

    if ([string]::IsNullOrEmpty($Texto)) { return @() }
    $resultado = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($Texto, '\[([^\]]*)\]\(([^)\s]+)\)')) {
        $destino = $m.Groups[2].Value
        if ($destino -match '^(https?://|#)') { continue }
        $resultado.Add($destino)
    }
    return @($resultado.ToArray())
}

# Caminhos citados por link relativo (já limpos) ou entre crases com forma de caminho.
function Get-CaminhosCitados {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Texto)

    if ([string]::IsNullOrEmpty($Texto)) { return @() }
    $resultado = New-Object System.Collections.Generic.List[string]

    foreach ($destino in @(Get-LinksRelativos -Texto $Texto)) {
        $limpo = ConvertTo-DestinoLimpo -Destino $destino
        if ($limpo -ne '' -and -not $resultado.Contains($limpo)) { $resultado.Add($limpo) }
    }

    foreach ($m in [regex]::Matches($Texto, '`([^`\r\n]+)`')) {
        $trecho = $m.Groups[1].Value.Trim()
        if ($trecho -match '\s' -or $trecho -match '^(https?://|#)') { continue }
        if ($trecho -match '/' -or $trecho -match '\.(md|png|pdf|ps1|txt)$') {
            if (-not $resultado.Contains($trecho)) { $resultado.Add($trecho) }
        }
    }
    return @($resultado.ToArray())
}

# Verdadeiro se o caminho relativo resolve para um arquivo (não pasta) sob a raiz.
function Test-ArquivoExiste {
    param([string]$Raiz, [string]$Caminho)
    if ([string]::IsNullOrWhiteSpace($Caminho)) { return $false }
    try {
        return (Test-Path -LiteralPath (Join-Path $Raiz $Caminho) -PathType Leaf)
    }
    catch { return $false }
}

# Destinos relativos do README que não existem como arquivo.
function Find-LinksQuebrados {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Raiz,
        [AllowEmptyString()][AllowNull()][string]$TextoReadme
    )

    $quebrados = New-Object System.Collections.Generic.List[string]
    foreach ($destino in @(Get-LinksRelativos -Texto $TextoReadme)) {
        $limpo = ConvertTo-DestinoLimpo -Destino $destino
        if (-not (Test-ArquivoExiste -Raiz $Raiz -Caminho $limpo)) { $quebrados.Add($destino) }
    }
    return @($quebrados.ToArray())
}

# Caminhos citados que existem como arquivo e têm 0 bytes.
function Find-ArquivosVazios {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Raiz,
        [AllowEmptyCollection()][string[]]$Caminhos = @()
    )

    $vazios = New-Object System.Collections.Generic.List[string]
    foreach ($c in $Caminhos) {
        if (-not (Test-ArquivoExiste -Raiz $Raiz -Caminho $c)) { continue }
        if ((Get-Item -LiteralPath (Join-Path $Raiz $c)).Length -eq 0) { $vazios.Add($c) }
    }
    return @($vazios.ToArray())
}

# Títulos obrigatórios do README, na ordem do Glossário.
$script:SecoesObrigatorias = @(
    'Tema e objetivo',
    'Fontes e por que são confiáveis',
    'Diretriz de comportamento',
    'Perguntas, respostas e fontes',
    'Link do notebook'
)

# Títulos Markdown (#..######) do texto, sem numeração inicial ("1.", "1)") e sem espaços nas pontas.
# Retorna objetos com Titulo, Indice (posição da linha) e Linha.
function Get-TitulosMarkdown {
    param([AllowEmptyString()][AllowNull()][string]$Texto)

    $lista = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrEmpty($Texto)) { return @() }
    $linhas = $Texto -split "\r?\n"
    for ($i = 0; $i -lt $linhas.Count; $i++) {
        if ($linhas[$i] -match '^#{1,6}\s+(.*)$') {
            $t = $Matches[1].Trim()
            $t = ($t -replace '^\d+[.)]\s+', '').Trim()
            $lista.Add([pscustomobject]@{ Titulo = $t; Indice = $i })
        }
    }
    return @($lista.ToArray())
}

# Títulos obrigatórios ausentes, repetidos (mais de uma ocorrência) ou fora da ordem do Glossário.
# Comparação exata (maiúsculas, minúsculas e acentos importam).
function Find-SecoesFaltantes {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$TextoReadme)

    $titulos = @(Get-TitulosMarkdown -Texto $TextoReadme)
    $faltantes = New-Object System.Collections.Generic.List[string]
    $maiorPosicao = -1
    foreach ($nome in $script:SecoesObrigatorias) {
        $ocorrencias = @($titulos | Where-Object { $_.Titulo -ceq $nome })
        if ($ocorrencias.Count -ne 1) { $faltantes.Add($nome); continue }
        $pos = $ocorrencias[0].Indice
        if ($pos -lt $maiorPosicao) { $faltantes.Add($nome); continue }
        $maiorPosicao = $pos
    }
    return @($faltantes.ToArray())
}

# Ocorrências dos Termos_de_Placeholder: [PREENCHER: ...], TODO, TBD, XXX (palavra inteira) e lorem ipsum.
# Sem diferenciar maiúsculas de minúsculas.
function Find-Placeholders {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Texto)

    if ([string]::IsNullOrEmpty($Texto)) { return @() }
    $padrao = '\[PREENCHER:[^\]]*\]|\b(?:TODO|TBD|XXX)\b|lorem\s+ipsum'
    $opcoes = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
              [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    $achados = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($Texto, $padrao, $opcoes)) { $achados.Add($m.Value) }
    return @($achados.ToArray())
}

# Valida a seção "Link do notebook": exatamente uma URL https:// e nenhum Placeholder.
# Não altera nada (Requirement 9.5). Retorna objeto com Valido e Motivo.
function Test-LinkNotebook {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$TextoReadme)

    $invalido = { param($detalhe) [pscustomobject]@{ Valido = $false; Motivo = "Link do Notebook inválido: $detalhe" } }

    if ([string]::IsNullOrEmpty($TextoReadme)) { return (& $invalido 'seção ausente') }
    $linhas = $TextoReadme -split "\r?\n"
    $titulos = @(Get-TitulosMarkdown -Texto $TextoReadme)
    $inicio = $titulos | Where-Object { $_.Titulo -ceq 'Link do notebook' } | Select-Object -First 1
    if ($null -eq $inicio) { return (& $invalido 'seção ausente') }

    $fim = $linhas.Count
    $proximo = $titulos | Where-Object { $_.Indice -gt $inicio.Indice } | Select-Object -First 1
    if ($null -ne $proximo) { $fim = $proximo.Indice }

    $corpo = ''
    if ($fim -gt $inicio.Indice + 1) {
        $corpo = ($linhas[($inicio.Indice + 1)..($fim - 1)]) -join "`n"
    }
    if ([string]::IsNullOrWhiteSpace($corpo)) { return (& $invalido 'seção vazia') }

    if (@(Find-Placeholders -Texto $corpo).Count -gt 0) { return (& $invalido 'contém Placeholder') }

    $urls = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($corpo, '[A-Za-z][A-Za-z0-9+.\-]*://[^\s<>)\]]+')) {
        $urls.Add($m.Value.TrimEnd('.', ',', ';', ':', '!', '?'))
    }
    $https = @($urls | Where-Object { $_ -cmatch '^https://\S+' })
    if ($urls.Count -ne $https.Count) { return (& $invalido 'URL não inicia com https://') }
    if ($https.Count -eq 0) { return (& $invalido 'nenhuma URL https:// encontrada') }
    if ($https.Count -gt 1) { return (& $invalido 'mais de uma URL https:// encontrada') }

    return [pscustomobject]@{ Valido = $true; Motivo = '' }
}

# Termos da lista que aparecem no texto. Linhas em branco são ignoradas.
# DECISÃO DO USUÁRIO (altera o design original, que previa subcadeia): cada termo casa apenas
# como palavra/expressão inteira, com limites Unicode (letras e dígitos), sem diferenciar
# maiúsculas de minúsculas. Motivo: um termo curto casava com "áudio", "Estúdio" e "idioma".
function Find-TermosProibidos {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Texto,
        [AllowEmptyCollection()][AllowNull()][string[]]$Termos = @()
    )

    $encontrados = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrEmpty($Texto) -or $null -eq $Termos) { return @() }
    $opcoes = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
              [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    foreach ($termo in $Termos) {
        if ([string]::IsNullOrWhiteSpace($termo)) { continue }
        $t = $termo.Trim()
        $padrao = '(?<![\p{L}\p{N}])' + [regex]::Escape($t) + '(?![\p{L}\p{N}])'
        if ([regex]::IsMatch($Texto, $padrao, $opcoes) -and -not $encontrados.Contains($t)) {
            $encontrados.Add($t)
        }
    }
    return @($encontrados.ToArray())
}

# Verdadeiro se o nome segue a convenção de materiais: ^[a-z0-9-]+\.[a-z0-9]+$ e total <= 100 (Req. 8.6).
function Test-NomeArquivoMaterial {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Nome)

    if ([string]::IsNullOrEmpty($Nome)) { return $false }
    if ($Nome.Length -gt 100) { return $false }
    return [regex]::IsMatch($Nome, '^[a-z0-9-]+\.[a-z0-9]+\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
}

# Nome corrigido sugerido para um arquivo fora da convenção (Req. 8.7).
# Minúsculas, remoção de acentos (NFD), espaços e underscores viram hífen, demais caracteres
# inválidos são removidos, hífens repetidos colapsam, hífens das pontas do nome base são aparados
# e o nome base é truncado para que o total fique em no máximo 100 caracteres.
function Get-NomeSugerido {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Nome)

    # Nome já válido é devolvido igual (ex.: hífens duplos ou nas pontas são permitidos pela convenção).
    if (Test-NomeArquivoMaterial -Nome $Nome) { return $Nome }

    $limite = 100
    $texto = if ($null -eq $Nome) { '' } else { $Nome }

    $decomposto = $texto.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $decomposto.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -eq [System.Globalization.UnicodeCategory]::NonSpacingMark) { continue }
        [void]$sb.Append($c)
    }
    $texto = $sb.ToString().ToLowerInvariant()

    $ponto = $texto.LastIndexOf('.')
    if ($ponto -ge 0) {
        $base = $texto.Substring(0, $ponto)
        $ext = $texto.Substring($ponto + 1)
    }
    else {
        $base = $texto
        $ext = ''
    }

    $base = $base -replace '[\s_]+', '-'
    $base = $base -replace '[^a-z0-9-]', ''
    $base = ($base -replace '-{2,}', '-').Trim('-')
    $ext = $ext -replace '[^a-z0-9]', ''
    if ($ext.Length -gt ($limite - 2)) { $ext = $ext.Substring(0, $limite - 2) }

    if ($base -eq '') { $base = 'arquivo' }
    $maxBase = if ($ext -ne '') { $limite - 1 - $ext.Length } else { $limite }
    if ($base.Length -gt $maxBase) { $base = $base.Substring(0, $maxBase).Trim('-') }
    if ($base -eq '') { $base = 'a' }

    if ($ext -eq '') { return $base }
    return "$base.$ext"
}

# Valida a frase de Tema: 1 a 300 caracteres (após aparar), sem quebra de linha, terminada em um único ponto final.
function Test-FraseTema {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Tema)

    $resultado = { param($ok, $motivo) [pscustomobject]@{ Valido = $ok; Motivo = $motivo } }

    if ([string]::IsNullOrWhiteSpace($Tema)) { return (& $resultado $false 'Tema vazio ou composto apenas por espaços.') }
    $t = $Tema.Trim()
    if ($t.Length -gt 300) { return (& $resultado $false 'Tema com mais de 300 caracteres.') }
    if ($t -match '[\r\n]') { return (& $resultado $false 'Tema não pode conter quebra de linha.') }
    if (-not $t.EndsWith('.')) { return (& $resultado $false 'Tema deve terminar em um ponto final.') }
    if ($t.EndsWith('..')) { return (& $resultado $false 'Tema deve terminar em um único ponto final.') }
    return (& $resultado $true '')
}

# Valida a Diretriz de Comportamento (Req. 5.1 a 5.4).
function Test-Diretriz {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$Texto,
        [AllowEmptyString()][AllowNull()][string]$Tema
    )

    $resultado = { param($ok, $motivo) [pscustomobject]@{ Valido = $ok; Motivo = $motivo } }

    if ([string]::IsNullOrWhiteSpace($Texto)) { return (& $resultado $false 'Diretriz vazia.') }
    if ($Texto.Length -gt 4000) { return (& $resultado $false 'Diretriz com mais de 4.000 caracteres.') }

    $prefixo = 'Comporte-se como um especialista em ' + $(if ($null -eq $Tema) { '' } else { $Tema.Trim() })
    if (-not $Texto.StartsWith($prefixo, [System.StringComparison]::Ordinal)) {
        return (& $resultado $false 'A primeira frase deve começar com "Comporte-se como um especialista em " seguido do Tema.')
    }

    $opcoes = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
              [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    if (-not [regex]::IsMatch($Texto, 'portugu[êe]s\s+do\s+Brasil', $opcoes)) {
        return (& $resultado $false 'Falta a instrução de responder sempre em português do Brasil.')
    }
    if (-not ([regex]::IsMatch($Texto, '\bfonte', $opcoes) -and
              [regex]::IsMatch($Texto, 'nome\s+do\s+documento', $opcoes) -and
              [regex]::IsMatch($Texto, '\bfinal\b', $opcoes))) {
        return (& $resultado $false 'Falta a instrução de indicar a Fonte (nome do documento) ao final de cada afirmação.')
    }
    if (-not [regex]::IsMatch($Texto, 'conhecimento\s+externo', $opcoes)) {
        return (& $resultado $false 'Falta a instrução de declarar a limitação sem usar conhecimento externo às Fontes.')
    }
    return (& $resultado $true '')
}

# Conteúdo do bloco de código da seção "Diretriz de comportamento" do README: o texto entre a linha
# de abertura da cerca e a linha de fechamento, sem remover a quebra de linha que antecede o fechamento.
# Aceita cercas com 3 ou mais acentos graves (o fechamento precisa ter ao menos o mesmo tamanho).
# Retorna $null se a seção, a cerca de abertura ou a de fechamento não existir.
function Get-BlocoDiretriz {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$TextoReadme)

    if ([string]::IsNullOrEmpty($TextoReadme)) { return $null }

    $linhas = New-Object System.Collections.Generic.List[object]
    foreach ($m in [regex]::Matches($TextoReadme, '([^\r\n]*)(\r\n|\n|\r|$)')) {
        if ($m.Length -eq 0) { continue }
        $linhas.Add([pscustomobject]@{ Inicio = $m.Index; Fim = $m.Index + $m.Length; Conteudo = $m.Groups[1].Value })
    }

    $i = 0
    $achou = $false
    for (; $i -lt $linhas.Count; $i++) {
        if ($linhas[$i].Conteudo -cmatch '^#{1,6}\s+(?:\d+[.)]\s+)?Diretriz de comportamento\s*$') { $achou = $true; break }
    }
    if (-not $achou) { return $null }

    $tamanho = 0
    $inicioConteudo = -1
    for ($i = $i + 1; $i -lt $linhas.Count; $i++) {
        $c = $linhas[$i].Conteudo
        if ($c -match '^ {0,3}(`{3,})[^`]*$') {
            $tamanho = $Matches[1].Length
            $inicioConteudo = $linhas[$i].Fim
            break
        }
        if ($c -match '^#{1,6}\s') { return $null }
    }
    if ($inicioConteudo -lt 0) { return $null }

    for ($j = $i + 1; $j -lt $linhas.Count; $j++) {
        if ($linhas[$j].Conteudo -match '^ {0,3}(`{3,})\s*$' -and $Matches[1].Length -ge $tamanho) {
            return $TextoReadme.Substring($inicioConteudo, $linhas[$j].Inicio - $inicioConteudo)
        }
    }
    return $null
}

# Lê um critério booleano de um objeto, hashtable ou ausente (ausente = não atendido).
function Get-ValorCriterio {
    param($Origem, [string]$Nome)
    if ($null -eq $Origem) { return $false }
    if ($Origem -is [System.Collections.IDictionary]) {
        if ($Origem.Contains($Nome)) { return [bool]$Origem[$Nome] }
        return $false
    }
    $p = $Origem.PSObject.Properties[$Nome]
    if ($null -ne $p) { return [bool]$p.Value }
    return $false
}

# Decide o status de uma Fonte: "aprovada" ou "descartada" (Req. 4.4 a 4.7).
# -Criterios: objeto ou hashtable com Autoria, Instituicao, DataPublicacao, Referencias e AcessoPublico
#             (ou um array de 5 booleanos nessa ordem).
# aprovada = Autoria E AcessoPublico E (>= 3 critérios) E NÃO DadoPessoal E CompartilhamentoPermitido E LinkAcessivel.
function Get-StatusFonte {
    [CmdletBinding()]
    param(
        $Criterios,
        [bool]$DadoPessoal = $false,
        [bool]$CompartilhamentoPermitido = $true,
        [bool]$LinkAcessivel = $true
    )

    $nomes = @('Autoria', 'Instituicao', 'DataPublicacao', 'Referencias', 'AcessoPublico')
    $v = @{}
    if ($Criterios -is [System.Array]) {
        for ($k = 0; $k -lt $nomes.Count; $k++) {
            $v[$nomes[$k]] = ($k -lt $Criterios.Count) -and [bool]$Criterios[$k]
        }
    }
    else {
        foreach ($n in $nomes) { $v[$n] = Get-ValorCriterio -Origem $Criterios -Nome $n }
    }
    $atendidos = @($nomes | Where-Object { $v[$_] }).Count

    if ($v['Autoria'] -and $v['AcessoPublico'] -and $atendidos -ge 3 -and
        -not $DadoPessoal -and $CompartilhamentoPermitido -and $LinkAcessivel) {
        return 'aprovada'
    }
    return 'descartada'
}

# Conta as perguntas válidas do Registro de Perguntas (Req. 7.2, 7.3, 7.4, 7.6, 7.7).
# -Linhas: linhas da tabela Markdown (| nº | pergunta | resposta | Fontes citadas | Print de Chat |).
# Válida = ao menos uma Fonte citada (diferente de "sem citação") e Print de Chat cujo link relativo
# resolve para um arquivo de imagem existente sob -Raiz.
function Measure-PerguntasValidas {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][AllowNull()][string[]]$Linhas = @(),
        [Parameter(Mandatory)][string]$Raiz
    )

    $total = 0
    if ($null -eq $Linhas) { return 0 }
    foreach ($linha in $Linhas) {
        if ([string]::IsNullOrWhiteSpace($linha)) { continue }
        $t = $linha.Trim()
        if (-not $t.StartsWith('|')) { continue }
        $t = $t.Trim('|')
        $celulas = @($t -split '\|' | ForEach-Object { $_.Trim() })
        if ($celulas.Count -lt 5) { continue }
        if ($celulas[0] -notmatch '^\d+$') { continue }   # cabeçalho e separador

        $fontes = $celulas[3]
        if ([string]::IsNullOrWhiteSpace($fontes) -or $fontes -match '^\s*sem\s+cita[çc][ãa]o\s*$') { continue }

        $print = $celulas[4]
        if ($print -match '\]\(([^)\s]+)\)') { $destino = $Matches[1] }
        else { $destino = $print.Trim('`', ' ') }
        if ($destino -match '^(https?://|#)' -or [string]::IsNullOrWhiteSpace($destino)) { continue }
        $limpo = ConvertTo-DestinoLimpo -Destino $destino
        if ($limpo -notmatch '\.(png|jpe?g|gif|webp)$') { continue }
        if (-not (Test-ArquivoExiste -Raiz $Raiz -Caminho $limpo)) { continue }
        $total++
    }
    return $total
}

# Verdadeiro se a URL do remoto origin é https://github.com/Gtvnv/axios-segundo-cerebro após
# normalização (sem .git e sem barra final, sem diferenciar maiúsculas de minúsculas) (Req. 11.1).
function Test-RemoteOrigin {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    $u = $Url.Trim().TrimEnd('/')
    if ($u.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) { $u = $u.Substring(0, $u.Length - 4) }
    $u = $u.TrimEnd('/')
    return [string]::Equals($u, 'https://github.com/Gtvnv/axios-segundo-cerebro', [System.StringComparison]::OrdinalIgnoreCase)
}

# Lê um arquivo de texto como UTF-8; retorna '' se estiver vazio.
function Read-TextoArquivo {
    param([string]$Caminho)
    $t = Get-Content -LiteralPath $Caminho -Raw -Encoding UTF8
    if ($null -eq $t) { return '' }
    return $t
}

# Caminho relativo à raiz, com "/" como separador.
function Get-CaminhoRelativo {
    param([string]$Raiz, [string]$Completo)
    $base = [System.IO.Path]::GetFullPath($Raiz).TrimEnd('\', '/')
    $rel = [System.IO.Path]::GetFullPath($Completo)
    if ($rel.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $rel.Substring($base.Length)
    }
    return $rel.TrimStart('\', '/').Replace('\', '/')
}

# Arquivo existe e tem conteúdo não vazio (ao menos um caractere que não seja espaço).
function Test-ArquivoComConteudo {
    param([string]$Caminho)
    if (-not (Test-Path -LiteralPath $Caminho -PathType Leaf)) { return $false }
    return (-not [string]::IsNullOrWhiteSpace((Read-TextoArquivo -Caminho $Caminho)))
}

# Executa as seis verificações na ordem do design, sem parar na primeira falha.
# Retorna objetos { Id, Descricao, Ok, Detalhes }.
function Invoke-Validacao {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Raiz)

    $readme = Join-Path $Raiz 'README.md'
    $arquivoTermos = Join-Path (Join-Path $Raiz 'scripts') 'termos-proibidos.txt'
    $readmeOk = Test-ArquivoComConteudo -Caminho $readme
    $textoReadme = ''
    if ($readmeOk) {
        try { $textoReadme = Read-TextoArquivo -Caminho $readme } catch { $readmeOk = $false }
    }
    $msgReadme = 'README.md ausente ou vazio'

    $verificacoes = @(
        @{ Id = 1; Descricao = 'Links relativos do README apontam para arquivos existentes'; Dep = 'readme'
           Bloco = { @(Find-LinksQuebrados -Raiz $Raiz -TextoReadme $textoReadme) } },
        @{ Id = 2; Descricao = 'Arquivos citados no README têm mais de 0 bytes'; Dep = 'readme'
           Bloco = {
               $citados = @(Get-CaminhosCitados -Texto $textoReadme)
               @(Find-ArquivosVazios -Raiz $Raiz -Caminhos $citados)
           } },
        @{ Id = 3; Descricao = 'README contém as cinco seções obrigatórias'; Dep = 'readme'
           Bloco = { @(Find-SecoesFaltantes -TextoReadme $textoReadme) | ForEach-Object { "seção ausente, repetida ou fora de ordem: $_" } } },
        @{ Id = 4; Descricao = 'README e docs/*.md sem Termos_de_Placeholder'; Dep = ''
           Bloco = {
               $alvos = New-Object System.Collections.Generic.List[string]
               if (Test-Path -LiteralPath $readme -PathType Leaf) { $alvos.Add($readme) }
               $docs = Join-Path $Raiz 'docs'
               if (Test-Path -LiteralPath $docs -PathType Container) {
                   foreach ($f in @(Get-ChildItem -LiteralPath $docs -Filter '*.md' -File -Force)) { $alvos.Add($f.FullName) }
               }
               $det = New-Object System.Collections.Generic.List[string]
               foreach ($a in $alvos) {
                   $rel = Get-CaminhoRelativo -Raiz $Raiz -Completo $a
                   foreach ($p in @(Find-Placeholders -Texto (Read-TextoArquivo -Caminho $a))) { $det.Add("${rel}: $p") }
               }
               @($det.ToArray())
           } },
        @{ Id = 5; Descricao = 'Link do Notebook começa com https://'; Dep = 'readme'
           Bloco = {
               $r = Test-LinkNotebook -TextoReadme $textoReadme
               if ($r.Valido) { @() } else { @($r.Motivo) }
           } },
        @{ Id = 6; Descricao = 'Arquivos de texto sem termos proibidos'; Dep = 'termos'
           Bloco = {
               $termos = @(Get-Content -LiteralPath $arquivoTermos -Encoding UTF8 |
                   ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
               $nomesTexto = @('.gitignore', '.gitkeep')
               $extTexto = @('.md', '.txt', '.ps1', '.json')
               $excluido = [System.IO.Path]::GetFullPath($arquivoTermos)
               $det = New-Object System.Collections.Generic.List[string]
               foreach ($f in @(Get-ChildItem -LiteralPath $Raiz -Recurse -File -Force)) {
                   $rel = Get-CaminhoRelativo -Raiz $Raiz -Completo $f.FullName
                   if ($rel -match '(^|/)\.git/') { continue }
                   if ([string]::Equals([System.IO.Path]::GetFullPath($f.FullName), $excluido, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                   if (-not (($extTexto -contains $f.Extension.ToLowerInvariant()) -or ($nomesTexto -contains $f.Name))) { continue }
                   $texto = Read-TextoArquivo -Caminho $f.FullName
                   foreach ($t in @(Find-TermosProibidos -Texto $texto -Termos $termos)) { $det.Add("${rel}: $t") }
               }
               @($det.ToArray())
           } }
    )

    $resultados = New-Object System.Collections.Generic.List[object]
    foreach ($v in $verificacoes) {
        $ok = $true
        $detalhes = @()
        try {
            if ($v.Dep -eq 'readme' -and -not $readmeOk) {
                $ok = $false
                $detalhes = @($msgReadme)
            }
            elseif ($v.Dep -eq 'termos' -and -not (Test-ArquivoComConteudo -Caminho $arquivoTermos)) {
                $ok = $false
                $detalhes = @('termos-proibidos.txt ausente ou vazio')
            }
            elseif ($v.Id -eq 6 -and @(Get-Content -LiteralPath $arquivoTermos -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }).Count -eq 0) {
                $ok = $false
                $detalhes = @('termos-proibidos.txt ausente ou vazio')
            }
            else {
                $detalhes = @(& $v.Bloco)
                $ok = ($detalhes.Count -eq 0)
            }
        }
        catch {
            $ok = $false
            $detalhes = @("Erro inesperado: $($_.Exception.Message)")
        }
        $resultados.Add([pscustomobject]@{
            Id        = $v.Id
            Descricao = $v.Descricao
            Ok        = $ok
            Detalhes  = @($detalhes)
        })
    }
    return @($resultados.ToArray())
}

# 0 se todos os resultados são OK; 1 caso contrário.
function Get-CodigoSaida {
    [CmdletBinding()]
    param([AllowEmptyCollection()][AllowNull()][object[]]$Resultados = @())

    if ($null -eq $Resultados) { return 0 }
    $falhas = @($Resultados | Where-Object { -not $_.Ok })
    if ($falhas.Count -gt 0) { return 1 }
    return 0
}

# Execução direta: roda a validação. Em dot-sourcing não executa nada.
if ($MyInvocation.InvocationName -ne '.') {
    $resultados = @(Invoke-Validacao -Raiz $Raiz)
    foreach ($r in $resultados) {
        $rotulo = if ($r.Ok) { 'OK    ' } else { 'FALHA ' }
        Write-Host "$rotulo $($r.Descricao)"
    }
    $falhas = @($resultados | Where-Object { -not $_.Ok })
    if ($falhas.Count -gt 0) {
        Write-Host 'Detalhes das falhas:'
        foreach ($f in $falhas) {
            Write-Host "- $($f.Descricao):"
            foreach ($d in @($f.Detalhes)) { Write-Host "    $d" }
        }
    }
    exit (Get-CodigoSaida -Resultados $resultados)
}
