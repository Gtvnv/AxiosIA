# Testes do fluxo de publicação (Pester 5+).
# Feature: axios-segundo-cerebro
# Rodar: Invoke-Pester ./tests/publicar.Tests.ps1
# Git, gh e Validador são sempre simulados: nenhum comando real e nenhuma rede.
# **Validates: Requirements 2.5, 2.6, 2.7, 2.8, 2.9, 9.6, 11.1, 11.2, 11.3, 11.4, 11.5, 11.6**

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'scripts' 'publicar.ps1')

    $script:UrlEsperada = 'https://github.com/Gtvnv/axios-segundo-cerebro'

    # Cria os três simuladores. Todos gravam as chamadas em $e.Chamadas (ordem preservada).
    # $e.Origin: URL devolvida por 'git remote get-url origin' ($null = ausente, código 2).
    # $e.Visibilidade: JSON/texto devolvido por 'gh repo view'; $e.ViewCodigo: código de saída.
    # $e.PushCodigo / $e.CriarCodigo / $e.CodigoValidador: códigos configuráveis.
    function New-Cenario {
        param(
            $Origin = 'https://github.com/Gtvnv/axios-segundo-cerebro.git',
            [string]$Visibilidade = '{"visibility":"PUBLIC"}',
            [int]$ViewCodigo = 0,
            [int]$PushCodigo = 0,
            [int]$CriarCodigo = 0,
            [int]$CodigoValidador = 0
        )
        $e = @{
            Chamadas = [System.Collections.Generic.List[string]]::new()
            Origin = $Origin; Visibilidade = $Visibilidade; ViewCodigo = $ViewCodigo
            PushCodigo = $PushCodigo; CriarCodigo = $CriarCodigo; CodigoValidador = $CodigoValidador
        }
        $e.Git = {
            $e.Chamadas.Add('git ' + ($args -join ' '))
            if ($args[0] -eq 'remote') {
                if ($null -eq $e.Origin) { $global:LASTEXITCODE = 2; return }
                $global:LASTEXITCODE = 0; return $e.Origin
            }
            if ($args[0] -eq 'push') {
                $global:LASTEXITCODE = $e.PushCodigo
                if ($e.PushCodigo -ne 0) { return 'push rejeitado' }
                return
            }
            $global:LASTEXITCODE = 0
        }.GetNewClosure()
        $e.Gh = {
            $e.Chamadas.Add('gh ' + ($args -join ' '))
            if ($args[1] -eq 'create') {
                $global:LASTEXITCODE = $e.CriarCodigo
                if ($e.CriarCodigo -ne 0) { return 'erro ao criar' }
                return
            }
            $global:LASTEXITCODE = $e.ViewCodigo
            if ($e.ViewCodigo -ne 0) { return 'gh falhou' }
            return $e.Visibilidade
        }.GetNewClosure()
        $e.Validador = {
            param($RaizValidar)
            $e.Chamadas.Add('validador')
            $e.CodigoValidador
        }.GetNewClosure()
        $e
    }

    function Invoke-Cenario {
        param($E, [switch]$Autorizado)
        Invoke-Publicacao -Autorizado:$Autorizado -Raiz $TestDrive `
            -Git $E.Git -Gh $E.Gh -Validador $E.Validador
    }
}

Describe 'Invoke-Publicacao' {
    It 'sem autorização não faz nenhuma chamada e entrega a lista de comandos (Req. 2.6)' {
        $e = New-Cenario
        $r = Invoke-Cenario -E $e
        $e.Chamadas.Count | Should -Be 0
        $r.Sucesso | Should -BeFalse
        $r.Status | Should -Be 'SemAutorizacao'
        $r.Comandos | Should -Contain 'git push -u origin main'
        $r.Comandos | Should -Contain "git remote add origin $($script:UrlEsperada).git"
    }

    It 'Validador com código 1 interrompe sem consultar git/gh nem push (Req. 9.6)' {
        $e = New-Cenario -CodigoValidador 1
        $r = Invoke-Cenario -E $e -Autorizado
        $r.Sucesso | Should -BeFalse
        $r.Status | Should -Be 'ValidadorFalhou'
        $e.Chamadas | Should -Be @('validador')
        ($e.Chamadas -match 'push').Count | Should -Be 0
    }

    It 'origin ausente + autorizado cria repositório público via gh e segue (Req. 2.5, 11.1)' {
        $e = New-Cenario -Origin $null
        $r = Invoke-Cenario -E $e -Autorizado
        $criar = @($e.Chamadas | Where-Object { $_ -like 'gh repo create*' })
        $criar.Count | Should -Be 1
        $criar[0] | Should -BeLike '*Gtvnv/axios-segundo-cerebro*'
        $criar[0] | Should -BeLike '*--public*'
        $criar[0] | Should -Not -BeLike '*--private*'
        $r.Sucesso | Should -BeTrue
    }

    It 'falha ao criar o repositório não repete nem faz push (Req. 2.7)' {
        $e = New-Cenario -Origin $null -CriarCodigo 1
        $r = Invoke-Cenario -E $e -Autorizado
        $r.Status | Should -Be 'CriacaoFalhou'
        @($e.Chamadas | Where-Object { $_ -like 'gh repo create*' }).Count | Should -Be 1
        ($e.Chamadas -match 'push').Count | Should -Be 0
    }

    It 'origin diferente informa URL encontrada e esperada, sem push (Req. 11.3)' {
        $outra = 'https://github.com/Outro/repo.git'
        $e = New-Cenario -Origin $outra
        $r = Invoke-Cenario -E $e -Autorizado
        $r.Sucesso | Should -BeFalse
        $r.Status | Should -Be 'OriginDiferente'
        $r.Mensagem | Should -BeLike "*$outra*"
        $r.Mensagem | Should -BeLike "*$($script:UrlEsperada)*"
        ($e.Chamadas -match 'push').Count | Should -Be 0
        ($e.Chamadas -match 'remote (set-url|add|remove)').Count | Should -Be 0
    }

    It 'visibilidade PRIVATE não faz push e orienta alterar no GitHub (Req. 11.4)' {
        $e = New-Cenario -Visibilidade '{"visibility":"PRIVATE"}'
        $r = Invoke-Cenario -E $e -Autorizado
        $r.Sucesso | Should -BeFalse
        $r.Status | Should -Be 'RepositorioNaoPublico'
        $r.Mensagem | Should -BeLike '*PRIVATE*'
        ($e.Chamadas -match 'push').Count | Should -Be 0
    }

    It 'erro do gh ao consultar visibilidade é indeterminado, sem push (Req. 11.5)' {
        $e = New-Cenario -ViewCodigo 1
        $r = Invoke-Cenario -E $e -Autorizado
        $r.Sucesso | Should -BeFalse
        $r.Status | Should -Be 'VisibilidadeIndeterminada'
        ($e.Chamadas -match 'push').Count | Should -Be 0
    }

    It 'resposta sem visibilidade é indeterminada, sem push (Req. 11.5)' {
        $e = New-Cenario -Visibilidade '{}'
        $r = Invoke-Cenario -E $e -Autorizado
        $r.Status | Should -Be 'VisibilidadeIndeterminada'
        ($e.Chamadas -match 'push').Count | Should -Be 0
    }

    It 'resposta não interpretável é indeterminada, sem push (Req. 11.5)' {
        $e = New-Cenario -Visibilidade 'isto não é json'
        $r = Invoke-Cenario -E $e -Autorizado
        $r.Status | Should -Be 'VisibilidadeIndeterminada'
        ($e.Chamadas -match 'push').Count | Should -Be 0
    }

    It 'push que falha é tentado uma única vez e devolve comandos manuais (Req. 2.7, 2.8)' {
        $e = New-Cenario -PushCodigo 1
        $r = Invoke-Cenario -E $e -Autorizado
        $r.Sucesso | Should -BeFalse
        $r.Status | Should -Be 'PushFalhou'
        @($e.Chamadas | Where-Object { $_ -like 'git push*' }).Count | Should -Be 1
        $r.Comandos | Should -Contain 'git push -u origin main'
    }

    It 'sucesso executa na ordem correta e informa o link do repositório (Req. 2.5, 2.9, 11.2, 11.6)' {
        $e = New-Cenario
        $r = Invoke-Cenario -E $e -Autorizado
        $r.Sucesso | Should -BeTrue
        $r.Status | Should -Be 'Publicado'
        $r.LinkSubmeter | Should -Be $script:UrlEsperada
        $r.Mensagem | Should -BeLike "*$($script:UrlEsperada)*"
        $e.Chamadas | Should -Be @(
            'validador'
            'git remote get-url origin'
            'gh repo view Gtvnv/axios-segundo-cerebro --json visibility'
            'git push -u origin main'
        )
    }

    It 'origin ausente com sucesso: validador, origin, create, view, push' {
        $e = New-Cenario -Origin $null
        $null = Invoke-Cenario -E $e -Autorizado
        $e.Chamadas[0] | Should -Be 'validador'
        $e.Chamadas[1] | Should -Be 'git remote get-url origin'
        $e.Chamadas[2] | Should -BeLike 'gh repo create*'
        $e.Chamadas[3] | Should -BeLike 'gh repo view*'
        $e.Chamadas[4] | Should -Be 'git push -u origin main'
    }

    It 'nenhuma chamada contém --force, --no-verify, reset --hard, add . nem add -A (Req. 2.8)' {
        $cenarios = @(
            (New-Cenario), (New-Cenario -Origin $null), (New-Cenario -PushCodigo 1),
            (New-Cenario -CodigoValidador 1), (New-Cenario -Visibilidade '{"visibility":"PRIVATE"}'),
            (New-Cenario -Origin 'https://github.com/Outro/repo.git'), (New-Cenario -ViewCodigo 1)
        )
        foreach ($e in $cenarios) {
            $null = Invoke-Cenario -E $e -Autorizado
            foreach ($c in $e.Chamadas) {
                $c | Should -Not -Match '--force|-f\b|--no-verify|reset --hard|\badd \.|\badd -A'
            }
        }
    }

    It 'dot-source de publicar.ps1 não executa nada' {
        $dir = Join-Path $TestDrive 'dot'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $script = Join-Path $PSScriptRoot '..' 'scripts' 'publicar.ps1'
        $saida = & pwsh -NoProfile -Command ". '$script'; 'fim'" 2>&1
        @($saida) | Should -Be @('fim')
    }
}
