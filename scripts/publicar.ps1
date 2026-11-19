<#
.SYNOPSIS
  Fluxo de publicação do repositório axios-segundo-cerebro no GitHub (Requirements 2 e 11).
.DESCRIPTION
  Sem -Autorizado, nada é executado: apenas a lista de comandos Git é entregue.
  Com -Autorizado: Validador -> verificação de origin -> (criação do repositório público
  se origin ausente) -> visibilidade -> git push -u origin main. Para na primeira falha,
  sem repetição automática. Nunca usa push --force, --no-verify, reset --hard,
  git add . nem git add -A, e não altera a configuração do git.
  Ao ser dot-sourced, este arquivo não executa nada.
#>
[CmdletBinding()]
param(
    [switch]$Autorizado,
    [string]$Raiz = (Split-Path -Parent $PSScriptRoot)
)

$script:UrlRepositorio = 'https://github.com/Gtvnv/axios-segundo-cerebro'
$script:NomeRepositorio = 'Gtvnv/axios-segundo-cerebro'

# Executa um scriptblock injetado (git/gh) e devolve Saida, Codigo e Erro.
# Falha = exceção ou $LASTEXITCODE diferente de 0.
function Invoke-Comando {
    param([scriptblock]$Bloco, [string[]]$Argumentos)
    $global:LASTEXITCODE = 0
    try {
        $saida = & $Bloco @Argumentos 2>&1
        $codigo = $global:LASTEXITCODE
        if ($null -eq $codigo) { $codigo = 0 }
        return [pscustomobject]@{ Saida = (@($saida) -join "`n").Trim(); Codigo = [int]$codigo; Erro = $null }
    }
    catch {
        return [pscustomobject]@{ Saida = ''; Codigo = 1; Erro = $_.Exception.Message }
    }
}

function Get-ComandosManuais {
    return @(
        "git remote add origin $($script:UrlRepositorio).git",
        'git push -u origin main'
    )
}

function New-ResultadoPublicacao {
    param([bool]$Sucesso, [string]$Status, [string]$Mensagem, [bool]$Parou = $true)
    $comandos = @()
    if (-not $Sucesso) { $comandos = Get-ComandosManuais }
    [pscustomobject]@{
        Sucesso      = $Sucesso
        Status       = $Status
        Mensagem     = $Mensagem
        LinkSubmeter = if ($Sucesso) { $script:UrlRepositorio } else { $null }
        Comandos     = $comandos
    }
}

function Invoke-Publicacao {
    [CmdletBinding()]
    param(
        [switch]$Autorizado,
        [string]$Raiz = (Split-Path -Parent $PSScriptRoot),
        [scriptblock]$Git = { git @args },
        [scriptblock]$Gh = { gh @args },
        # Retorna o código de saída do Validador (0 ou 1) como último inteiro emitido.
        [scriptblock]$Validador = {
            param($RaizValidar)
            & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'validar.ps1') -Raiz $RaizValidar
            $LASTEXITCODE
        }
    )

    # Sem autorização explícita: só entrega os comandos, sem executar nada (Req. 2.6).
    if (-not $Autorizado) {
        $r = New-ResultadoPublicacao -Sucesso $false -Status 'SemAutorizacao' `
            -Mensagem 'Publicação não autorizada. Nenhum comando foi executado. Para publicar manualmente, use os comandos listados.'
        return $r
    }

    if (-not (Get-Command Test-RemoteOrigin -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'validar.ps1')
    }

    $local = $null
    if ($Raiz -and (Test-Path -LiteralPath $Raiz -PathType Container)) {
        $local = Get-Location
        Set-Location -LiteralPath $Raiz
    }
    try {
        # 1. Validador (Req. 9.6): código diferente de 0 interrompe.
        $saidaVal = & $Validador $Raiz
        $codigoVal = @($saidaVal | Where-Object { $_ -is [int] }) | Select-Object -Last 1
        if ($null -eq $codigoVal) {
            return New-ResultadoPublicacao -Sucesso $false -Status 'ValidadorIndeterminado' `
                -Mensagem 'Não foi possível obter o código de saída do Validador. Publicação interrompida sem push.'
        }
        if ($codigoVal -ne 0) {
            return New-ResultadoPublicacao -Sucesso $false -Status 'ValidadorFalhou' `
                -Mensagem "O Validador terminou com código $codigoVal. Corrija as falhas e execute novamente. Nenhum push foi executado."
        }

        # 2. Remoto origin (Req. 11.1 e 11.3).
        $origin = Invoke-Comando -Bloco $Git -Argumentos @('remote', 'get-url', 'origin')
        $urlOrigin = if ($origin.Codigo -eq 0) { $origin.Saida } else { '' }

        if ([string]::IsNullOrWhiteSpace($urlOrigin)) {
            # Origin ausente e autorizado: cria o repositório público (Req. 2.5), sem repetição (Req. 2.7).
            $criar = Invoke-Comando -Bloco $Gh -Argumentos @('repo', 'create', $script:NomeRepositorio, '--public', '--source', '.', '--remote', 'origin')
            if ($criar.Codigo -ne 0) {
                $causa = if ($criar.Erro) { $criar.Erro } else { $criar.Saida }
                return New-ResultadoPublicacao -Sucesso $false -Status 'CriacaoFalhou' `
                    -Mensagem "Falha ao criar o repositório remoto: $causa. Sem nova tentativa automática. Use os comandos manuais."
            }
        }
        elseif (-not (Test-RemoteOrigin -Url $urlOrigin)) {
            return New-ResultadoPublicacao -Sucesso $false -Status 'OriginDiferente' `
                -Mensagem "O remoto origin aponta para '$urlOrigin', mas o esperado é '$($script:UrlRepositorio)'. Nenhum push foi executado e a configuração do git não foi alterada."
        }

        # 3. Visibilidade (Req. 11.2, 11.4, 11.5).
        $vis = Invoke-Comando -Bloco $Gh -Argumentos @('repo', 'view', $script:NomeRepositorio, '--json', 'visibility')
        $visibilidade = $null
        $motivo = $null
        if ($vis.Codigo -ne 0) {
            $motivo = if ($vis.Erro) { $vis.Erro } elseif ($vis.Saida) { $vis.Saida } else { "gh terminou com código $($vis.Codigo)" }
        }
        else {
            try {
                $visibilidade = ([string](($vis.Saida | ConvertFrom-Json -ErrorAction Stop).visibility)).Trim().ToUpperInvariant()
            }
            catch { $motivo = 'resposta do GitHub não pôde ser interpretada' }
            if (-not $motivo -and [string]::IsNullOrWhiteSpace($visibilidade)) { $motivo = 'a resposta do GitHub não informa a visibilidade' }
        }
        if ($motivo) {
            return New-ResultadoPublicacao -Sucesso $false -Status 'VisibilidadeIndeterminada' `
                -Mensagem "Não foi possível determinar a visibilidade do repositório: $motivo. Verificação não concluída; o repositório não é assumido como público. Nenhum push foi executado."
        }
        if ($visibilidade -ne 'PUBLIC') {
            return New-ResultadoPublicacao -Sucesso $false -Status 'RepositorioNaoPublico' `
                -Mensagem "O repositório está com visibilidade $visibilidade. A entrega exige repositório público: altere a visibilidade nas configurações do repositório no GitHub. Publicação não concluída; nenhum push foi executado."
        }

        # 4. Push (Req. 2.5), sem repetição e sem --force.
        $push = Invoke-Comando -Bloco $Git -Argumentos @('push', '-u', 'origin', 'main')
        if ($push.Codigo -ne 0) {
            $causa = if ($push.Erro) { $push.Erro } else { $push.Saida }
            return New-ResultadoPublicacao -Sucesso $false -Status 'PushFalhou' `
                -Mensagem "Falha no git push: $causa. Repositório local intacto; sem nova tentativa automática. Use os comandos manuais."
        }

        return New-ResultadoPublicacao -Sucesso $true -Status 'Publicado' `
            -Mensagem "Publicação concluída. O link a submeter é $($script:UrlRepositorio) (URL do repositório, não o Link do Notebook)."
    }
    finally {
        if ($local) { Set-Location -LiteralPath $local.Path }
    }
}

# Execução direta: em dot-sourcing não executa nada.
if ($MyInvocation.InvocationName -ne '.') {
    $resultado = Invoke-Publicacao -Autorizado:$Autorizado -Raiz $Raiz
    Write-Host $resultado.Mensagem
    if ($resultado.Comandos.Count -gt 0) {
        Write-Host 'Comandos Git para publicação manual:'
        $resultado.Comandos | ForEach-Object { Write-Host "  $_" }
    }
    if ($resultado.Sucesso) { exit 0 } else { exit 1 }
}
