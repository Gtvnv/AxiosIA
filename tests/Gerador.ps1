# Gerador de dados de teste do AXIOS (baseado em System.Random).
# Uso: . "$PSScriptRoot/Gerador.ps1"; Initialize-Gerador -Contexto 'Property 1'
#
# Todos os caracteres nao ASCII sao criados por ponto de codigo, para que o arquivo
# funcione igual no Windows PowerShell 5.1 e no PowerShell 7, com ou sem BOM.
# Nenhum termo proibido aparece literalmente aqui: eles sao montados por concatenacao.

Set-StrictMode -Version Latest

$script:GeradorRng = $null
$script:GeradorSemente = $null
$script:GeradorSementeSessao = $null

$script:TitulosSecoes = @(
    'Tema e objetivo',
    'Fontes e por que são confiáveis',
    'Diretriz de comportamento',
    'Perguntas, respostas e fontes',
    'Link do notebook'
)

# ---------------------------------------------------------------------------
# Semente
# ---------------------------------------------------------------------------

function Get-SementeBase {
    # Le AXIOS_SEED; se ausente ou invalida, sorteia uma unica vez por sessao.
    $texto = $env:AXIOS_SEED
    $valor = 0
    if (-not [string]::IsNullOrWhiteSpace($texto) -and [int]::TryParse($texto.Trim(), [ref]$valor)) {
        return $valor
    }
    if ($null -eq $script:GeradorSementeSessao) {
        $script:GeradorSementeSessao = [System.Random]::new().Next()
    }
    return $script:GeradorSementeSessao
}

function Initialize-Gerador {
    <#
    .SYNOPSIS
    Cria o System.Random do teste e imprime a semente no inicio dele.
    #>
    param(
        [string]$Contexto = 'teste',
        [Nullable[int]]$Semente = $null
    )
    $s = if ($null -ne $Semente) { [int]$Semente } else { Get-SementeBase }
    $script:GeradorSemente = $s
    $script:GeradorRng = [System.Random]::new($s)
    Write-Host ("[AXIOS_SEED] {0}: semente={1} (reproduzir com `$env:AXIOS_SEED={1})" -f $Contexto, $s)
    return $s
}

function Get-SementeAtual { return $script:GeradorSemente }

function Get-Rng {
    if ($null -eq $script:GeradorRng) { [void](Initialize-Gerador -Contexto 'implicito') }
    return $script:GeradorRng
}

# ---------------------------------------------------------------------------
# Primitivas
# ---------------------------------------------------------------------------

function New-Inteiro {
    # Inclusivo nos dois extremos.
    param([int]$Min, [int]$Max)
    return (Get-Rng).Next($Min, $Max + 1)
}

function New-Booleano { return ((Get-Rng).Next(0, 2) -eq 1) }

function Select-Aleatorio {
    param([object[]]$Itens)
    return $Itens[(Get-Rng).Next(0, $Itens.Count)]
}

function Select-Subconjunto {
    # Subconjunto aleatorio (ordem original preservada), com 0..n itens.
    param([object[]]$Itens)
    $r = @()
    foreach ($i in $Itens) { if (New-Booleano) { $r += $i } }
    return , $r
}

function Get-CaracteresUnicode {
    $pontos = @(
        0x00E1, 0x00E0, 0x00E3, 0x00E2, 0x00E9, 0x00EA, 0x00ED, 0x00F3, 0x00F4, 0x00F5, 0x00FA, 0x00E7,
        0x00C1, 0x00C3, 0x00C9, 0x00D3, 0x00C7, 0x00F1, 0x00FC, 0x00DF,
        0x0301, 0x0303,            # combinantes (forma NFD)
        0x03B1, 0x03A9, 0x0416, 0x0434, 0x4E2D, 0x6587, 0x3042, 0xD55C,
        0x2013, 0x2014, 0x2026, 0x00A0, 0x20AC
    )
    return $pontos | ForEach-Object { [char]::ConvertFromUtf32($_) }
}

function Get-CaracteresEmoji {
    return @(0x1F600, 0x1F4DA, 0x1F9E0) | ForEach-Object { [char]::ConvertFromUtf32($_) }
}

function New-StringAleatoria {
    <#
    .SYNOPSIS
    String aleatoria. -Alfabeto: Ascii, Alfanumerico, Unicode, Simbolos ou Misto.
    #>
    param(
        [int]$MinComprimento = 0,
        [int]$MaxComprimento = 40,
        [ValidateSet('Ascii', 'Alfanumerico', 'Unicode', 'Simbolos', 'Misto')]
        [string]$Alfabeto = 'Misto'
    )
    $alnum = [char[]]'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    $simb = [char[]]' !#$%&''()+,-.;=@[]^_`{}~'
    $uni = @(Get-CaracteresUnicode) + @(Get-CaracteresEmoji)
    $pool = switch ($Alfabeto) {
        'Alfanumerico' { $alnum }
        'Ascii' { $alnum + $simb }
        'Simbolos' { $simb }
        'Unicode' { $uni }
        default { $alnum + $simb + $uni }
    }
    $n = New-Inteiro -Min $MinComprimento -Max $MaxComprimento
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $n; $i++) { [void]$sb.Append([string](Select-Aleatorio $pool)) }
    return $sb.ToString()
}

function New-Palavra {
    param([int]$Min = 2, [int]$Max = 10)
    return (New-StringAleatoria -MinComprimento $Min -MaxComprimento $Max -Alfabeto Alfanumerico).ToLowerInvariant()
}

function New-Frase {
    param([int]$MinPalavras = 1, [int]$MaxPalavras = 12)
    $n = New-Inteiro -Min $MinPalavras -Max $MaxPalavras
    return ((1..$n | ForEach-Object { New-Palavra }) -join ' ')
}

function Set-CaixaAleatoria {
    # Troca a caixa de cada letra ao acaso (para testar comparacao sem diferenciar maiusculas).
    param([string]$Texto)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($c in $Texto.ToCharArray()) {
        if (New-Booleano) { [void]$sb.Append([char]::ToUpperInvariant($c)) }
        else { [void]$sb.Append([char]::ToLowerInvariant($c)) }
    }
    return $sb.ToString()
}

# ---------------------------------------------------------------------------
# Termos proibidos (montados em tempo de execucao)
# ---------------------------------------------------------------------------

function Join-Partes {
    # Monta um termo por concatenacao de partes: Join-Partes 'ab','cd' -> 'abcd'.
    param([string[]]$Partes)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($p in $Partes) { [void]$sb.Append($p) }
    return $sb.ToString()
}

function New-TermoProibidoSintetico {
    <#
    .SYNOPSIS
    Termo proibido de teste, montado em tempo de execucao a partir de partes aleatorias.
    Comeca com um prefixo fixo improvavel (qzx) para nao colidir com texto comum.
    #>
    param([int]$Partes = 2)
    $lista = @('q', 'z', 'x') + @(1..$Partes | ForEach-Object { New-Palavra -Min 3 -Max 6 })
    return (Join-Partes $lista)
}

function New-ListaTermosProibidos {
    # Linhas de um termos-proibidos.txt sintetico, com linhas em branco ao acaso.
    param([int]$Min = 1, [int]$Max = 5)
    $n = New-Inteiro -Min $Min -Max $Max
    $termos = @(1..$n | ForEach-Object { New-TermoProibidoSintetico })
    $linhas = @()
    foreach ($t in $termos) {
        $linhas += $t
        if (New-Booleano) { $linhas += '' }
    }
    return [pscustomobject]@{ Termos = $termos; Linhas = $linhas; Texto = ($linhas -join "`n") }
}

# ---------------------------------------------------------------------------
# Nomes de arquivo
# ---------------------------------------------------------------------------

function New-NomeArquivo {
    <#
    .SYNOPSIS
    Nome de arquivo com 1 a 150 caracteres, com Unicode, simbolos e espacos.
    -SeguroParaDisco remove o que o Windows nao aceita (\ / : * ? " < > |, ponto ou espaco no fim).
    -ComExtensao termina em ".ext" curta.
    #>
    param(
        [int]$MinComprimento = 1,
        [int]$MaxComprimento = 150,
        [switch]$SeguroParaDisco,
        [switch]$ComExtensao
    )
    $alvo = New-Inteiro -Min $MinComprimento -Max $MaxComprimento
    $ext = ''
    if ($ComExtensao) {
        $ext = '.' + (New-Palavra -Min 1 -Max 4)
        if ($alvo -le $ext.Length) { $alvo = $ext.Length + 1 }
    }
    $corpoLen = $alvo - $ext.Length
    $alfabeto = Select-Aleatorio @('Alfanumerico', 'Ascii', 'Unicode', 'Misto', 'Misto')
    $invalidos = [char[]]'\/:*?"<>|'
    $sb = [System.Text.StringBuilder]::new()
    while ($sb.Length -lt $corpoLen) {
        $c = New-StringAleatoria -MinComprimento 1 -MaxComprimento 1 -Alfabeto $alfabeto
        if ($SeguroParaDisco -and $c.IndexOfAny($invalidos) -ge 0) { continue }
        # Evita deixar um par substituto pela metade: pula emoji se so falta 1 posicao.
        if (($sb.Length + $c.Length) -gt $corpoLen) { [void]$sb.Append('a'); continue }
        [void]$sb.Append($c)
    }
    $corpo = $sb.ToString()
    if ($SeguroParaDisco) {
        $corpo = $corpo.TrimEnd('.', ' ')
        if ($corpo.Length -eq 0) { $corpo = 'a' }
        $corpo = $corpo.TrimStart(' ')
        if ($corpo.Length -eq 0) { $corpo = 'a' }
    }
    return $corpo + $ext
}

function New-NomeValidoMaterial {
    # Nome que obedece ^[a-z0-9-]+\.[a-z0-9]+$ com no maximo 100 caracteres (Requirement 8.6).
    $ext = New-Palavra -Min 1 -Max 5
    $max = 100 - $ext.Length - 1
    $corpo = (New-StringAleatoria -MinComprimento 1 -MaxComprimento $max -Alfabeto Alfanumerico).ToLowerInvariant()
    $corpo = (($corpo.ToCharArray() | ForEach-Object { if ((New-Inteiro 0 9) -eq 0) { '-' } else { $_ } }) -join '')
    return "$corpo.$ext"
}

# ---------------------------------------------------------------------------
# Markdown com links mistos
# ---------------------------------------------------------------------------

function New-MarkdownComLinks {
    <#
    .SYNOPSIS
    Texto Markdown com links relativos (existentes, inexistentes, pasta), externos, ancoras e mailto.
    Se -Raiz for informado, cria em disco os arquivos "existentes" (com 0 a poucos bytes).
    Retorna Texto, Existentes, Inexistentes, Pastas (links relativos, ja decodificados e sem ancora/consulta),
    Externos e Arquivos (mapa caminho relativo -> tamanho em bytes).
    #>
    param([string]$Raiz, [int]$MinLinks = 0, [int]$MaxLinks = 12)
    $n = New-Inteiro -Min $MinLinks -Max $MaxLinks
    $linhas = [System.Collections.Generic.List[string]]::new()
    $existentes = @(); $inexistentes = @(); $pastas = @(); $externos = @()
    $arquivos = [ordered]@{}
    $usados = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    for ($i = 0; $i -lt $n; $i++) {
        $tipo = Select-Aleatorio @('existente', 'existente', 'inexistente', 'pasta', 'externo', 'ancora', 'mailto')
        $rotulo = New-Frase -MinPalavras 1 -MaxPalavras 3
        $sufixo = Select-Aleatorio @('', '', ('#' + (New-Palavra)), ('?v=' + (New-Palavra)))
        switch ($tipo) {
            'existente' {
                $nome = (New-Palavra -Min 3 -Max 8) + $i
                if (New-Booleano) { $nome = $nome + ' ' + (New-Palavra -Min 1 -Max 4) }
                $rel = 'materiais/' + $nome + '.' + (New-Palavra -Min 1 -Max 3)
                if ($usados.Add($rel)) {
                    $tam = New-Inteiro -Min 0 -Max 5
                    $arquivos[$rel] = $tam
                    if ($Raiz) {
                        $caminho = Join-Path $Raiz $rel
                        New-Item -ItemType Directory -Force -Path (Split-Path $caminho -Parent) | Out-Null
                        [System.IO.File]::WriteAllBytes($caminho, [byte[]](1..$tam | ForEach-Object { 65 }))
                    }
                    $existentes += $rel
                    $dest = ($rel -replace ' ', '%20') + $sufixo
                    $linhas.Add("- [$rotulo]($dest)")
                }
            }
            'inexistente' {
                $rel = 'docs/' + (New-Palavra -Min 3 -Max 8) + "-ausente$i." + (New-Palavra -Min 1 -Max 3)
                if ($usados.Add($rel)) {
                    $inexistentes += $rel
                    $linhas.Add("- [$rotulo]($rel$sufixo)")
                }
            }
            'pasta' {
                $rel = 'materiais/pasta' + $i
                if ($usados.Add($rel)) {
                    if ($Raiz) { New-Item -ItemType Directory -Force -Path (Join-Path $Raiz $rel) | Out-Null }
                    $pastas += $rel
                    $linhas.Add("- [$rotulo]($rel)")
                }
            }
            'externo' {
                $url = (Select-Aleatorio @('https://', 'http://')) + (New-Palavra -Min 3 -Max 8) + '.example/' + (New-Palavra)
                $externos += $url
                $linhas.Add("- [$rotulo]($url)")
            }
            'ancora' { $linhas.Add("- [$rotulo](#" + (New-Palavra) + ')') }
            'mailto' { $linhas.Add("- [$rotulo](mailto:" + (New-Palavra) + '@example.org)') }
        }
        if (New-Booleano) { $linhas.Add((New-Frase)) }
    }
    return [pscustomobject]@{
        Texto        = ($linhas -join "`n")
        Existentes   = $existentes
        Inexistentes = $inexistentes
        Pastas       = $pastas
        Externos     = $externos
        Arquivos     = $arquivos
    }
}

# ---------------------------------------------------------------------------
# README com as cinco secoes e mutacoes
# ---------------------------------------------------------------------------

function New-Readme {
    <#
    .SYNOPSIS
    README sintetico valido com as cinco secoes na ordem do design.
    -Corpos permite fixar o corpo de cada secao (hashtable titulo -> texto).
    Retorna Texto e Secoes (lista ordenada de @{Titulo; Corpo; Numeracao}).
    #>
    param(
        [hashtable]$Corpos = @{},
        [switch]$Numerado,
        [switch]$ComGlossario
    )
    $secoes = [System.Collections.Generic.List[object]]::new()
    $k = 1
    foreach ($t in $script:TitulosSecoes) {
        $corpo = if ($Corpos.ContainsKey($t)) { $Corpos[$t] } else { New-Frase -MinPalavras 3 -MaxPalavras 10 }
        $num = ''
        if ($Numerado) { $num = "$k. " }
        $secoes.Add([pscustomobject]@{ Titulo = $t; Corpo = $corpo; Numeracao = $num })
        $k++
    }
    if ($ComGlossario) {
        $secoes.Add([pscustomobject]@{ Titulo = 'Glossário'; Corpo = (New-Frase); Numeracao = '' })
    }
    return [pscustomobject]@{ Secoes = $secoes; Texto = (ConvertTo-TextoReadme $secoes) }
}

function ConvertTo-TextoReadme {
    param([object[]]$Secoes, [string]$Titulo = 'AXIOS Segundo Cérebro')
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("# $Titulo`n`n" + (New-Frase) + "`n`n")
    foreach ($s in $Secoes) {
        [void]$sb.Append("## " + $s.Numeracao + $s.Titulo + "`n`n" + $s.Corpo + "`n`n")
    }
    return $sb.ToString()
}

function Edit-ReadmeMutacao {
    <#
    .SYNOPSIS
    Aplica uma mutacao ao README gerado por New-Readme e retorna Texto, Mutacao e Secoes.
    Mutacoes: Remover, Duplicar, Renomear, TrocarOrdem, Nenhuma.
    Para as quatro primeiras, Valido = $false (alguma regra de secoes deve falhar).
    #>
    param(
        [Parameter(Mandatory)][object]$Readme,
        [ValidateSet('Remover', 'Duplicar', 'Renomear', 'TrocarOrdem', 'Nenhuma', 'Aleatoria')]
        [string]$Mutacao = 'Aleatoria'
    )
    if ($Mutacao -eq 'Aleatoria') {
        $Mutacao = Select-Aleatorio @('Remover', 'Duplicar', 'Renomear', 'TrocarOrdem', 'Nenhuma')
    }
    $s = [System.Collections.Generic.List[object]]::new()
    foreach ($x in $Readme.Secoes) { $s.Add([pscustomobject]@{ Titulo = $x.Titulo; Corpo = $x.Corpo; Numeracao = $x.Numeracao }) }
    $obrig = $s.Count
    $idx = New-Inteiro -Min 0 -Max ($script:TitulosSecoes.Count - 1)
    switch ($Mutacao) {
        'Remover' { $s.RemoveAt($idx) }
        'Duplicar' { $s.Insert($idx, [pscustomobject]@{ Titulo = $s[$idx].Titulo; Corpo = (New-Frase); Numeracao = '' }) }
        'Renomear' {
            $novo = $s[$idx].Titulo
            # Troca por um titulo que nao e exato (caixa, sufixo ou letra removida).
            $novo = Select-Aleatorio @(($novo + 's'), $novo.ToUpperInvariant(), $novo.Substring(0, $novo.Length - 1), ($novo + ' extra'))
            $s[$idx].Titulo = $novo
        }
        'TrocarOrdem' {
            $a = New-Inteiro -Min 0 -Max ($script:TitulosSecoes.Count - 2)
            $tmp = $s[$a]; $s[$a] = $s[$a + 1]; $s[$a + 1] = $tmp
        }
    }
    return [pscustomobject]@{
        Mutacao = $Mutacao
        Valido  = ($Mutacao -eq 'Nenhuma')
        Secoes  = $s
        Texto   = (ConvertTo-TextoReadme $s)
    }
}

function Add-TermoAleatorio {
    # Insere um termo (com caixa aleatoria) em uma posicao aleatoria do texto.
    param([string]$Texto, [string]$Termo)
    $t = Set-CaixaAleatoria $Termo
    $pos = New-Inteiro -Min 0 -Max $Texto.Length
    return $Texto.Insert($pos, $t)
}

function New-Placeholder {
    # Variantes de Placeholder (com caixa aleatoria) que o Validador deve detectar.
    $variante = Select-Aleatorio @('PREENCHER', 'TODO', 'TBD', 'XXX', 'LOREM')
    switch ($variante) {
        'PREENCHER' { return Set-CaixaAleatoria ('[PREENCHER: ' + (New-Frase -MinPalavras 1 -MaxPalavras 4) + ']') }
        'LOREM' { return Set-CaixaAleatoria 'lorem ipsum' }
        default { return Set-CaixaAleatoria $variante }
    }
}

# ---------------------------------------------------------------------------
# Arvores de arquivos em TestDrive:
# ---------------------------------------------------------------------------

function New-ArvoreArquivos {
    <#
    .SYNOPSIS
    Cria uma arvore sintetica sob -Raiz (use $TestDrive ou "TestDrive:/x") e retorna o inventario.
    Cada arquivo tem Caminho (relativo, com /), Tipo (Texto ou Binario), Bytes e Conteudo.
    Estados de .git: Presente, Ausente (sorteado). Arquivos de texto podem receber termos em -Termos.
    #>
    param(
        [Parameter(Mandatory)][string]$Raiz,
        [int]$MinArquivos = 1,
        [int]$MaxArquivos = 8,
        [string[]]$Termos = @(),
        [switch]$ComGit
    )
    New-Item -ItemType Directory -Force -Path $Raiz | Out-Null
    $extTexto = @('.md', '.txt', '.ps1', '.json', '.gitkeep')
    $extBin = @('.png', '.pdf')
    $n = New-Inteiro -Min $MinArquivos -Max $MaxArquivos
    $inventario = [System.Collections.Generic.List[object]]::new()
    $usados = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $dirs = @('', 'docs', 'materiais', 'materiais/slides', 'scripts')

    for ($i = 0; $i -lt $n; $i++) {
        $binario = (New-Inteiro 0 3) -eq 0
        $ext = if ($binario) { Select-Aleatorio $extBin } else { Select-Aleatorio $extTexto }
        $nome = (New-Palavra -Min 2 -Max 8) + $i + $ext
        $dir = Select-Aleatorio $dirs
        $rel = if ($dir) { "$dir/$nome" } else { $nome }
        if (-not $usados.Add($rel)) { continue }
        $caminho = Join-Path $Raiz $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $caminho -Parent) | Out-Null
        if ($binario) {
            $bytes = [byte[]](1..(New-Inteiro 0 20) | ForEach-Object { New-Inteiro 0 255 })
            [System.IO.File]::WriteAllBytes($caminho, $bytes)
            $conteudo = $null
        }
        else {
            $conteudo = New-Frase -MinPalavras 0 -MaxPalavras 10
            foreach ($t in $Termos) { if (New-Booleano) { $conteudo = Add-TermoAleatorio -Texto $conteudo -Termo $t } }
            [System.IO.File]::WriteAllText($caminho, $conteudo, [System.Text.UTF8Encoding]::new($false))
        }
        $inventario.Add([pscustomobject]@{
                Caminho  = $rel
                Tipo     = if ($binario) { 'Binario' } else { 'Texto' }
                Bytes    = (Get-Item -LiteralPath $caminho).Length
                Conteudo = $conteudo
            })
    }
    if ($ComGit -or (New-Booleano)) {
        $g = Join-Path $Raiz '.git'
        New-Item -ItemType Directory -Force -Path $g | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $g 'config'), (New-Frase), [System.Text.UTF8Encoding]::new($false))
    }
    return [pscustomobject]@{ Raiz = $Raiz; Arquivos = $inventario }
}

function Get-HashArvore {
    # Instantaneo (caminho, tamanho, hash) para comparar antes e depois (Property 11).
    param([Parameter(Mandatory)][string]$Raiz)
    $base = (Resolve-Path -LiteralPath $Raiz).Path.TrimEnd('\', '/')
    $itens = Get-ChildItem -LiteralPath $Raiz -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        $h = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        '{0}|{1}|{2}' -f $_.FullName.Substring($base.Length), $_.Length, $h
    }
    return @($itens)
}
