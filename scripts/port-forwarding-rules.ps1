# Запрашиваем вывод docker ps из WSL. Указываем формат, чтобы получить только колонку PORTS
$dockerOutput = wsl --exec docker ps --format "{{.Ports}}"

# Инициализируем пустой массив для портов
$Ports = @()

# Обрабатываем каждую строку вывода
foreach ($line in $dockerOutput) {
    # Ищем паттерн привязки к IPv4, например: 0.0.0.0:3000->8080/tcp
    if ($line -match '0\.0\.0\.0:(\d+)->') {
        # Извлекаем порт из первой группы захвата и конвертируем в число
        $port = [int]$matches[1]
        
        # Добавляем в массив, если такого порта там еще нет (защита от дублей)
        if ($port -notin $Ports) {
            $Ports += $port
        }
    }
}

# Сортируем порты для удобства и выводим результат
$Ports = $Ports | Sort-Object
Write-Host "Найдены открытые порты: $($Ports -join ', ')" -ForegroundColor Green

# Получаем актуальный IP-адрес WSL
$wslIp = (wsl --exec hostname -I).Trim().Split(" ")[0]
Write-Host "Актуальный IP WSL: $wslIp" -ForegroundColor Green

foreach ($Port in $Ports) {
    # 1. Обновляем проброс портов (portproxy)
    netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 | Out-Null
    netsh interface portproxy add v4tov4 listenport=$Port listenaddress=0.0.0.0 connectport=$Port connectaddress=$wslIp

    # 2. Обновляем правила брандмауэра для всех профилей сети (Public, Private, Domain)
    $RuleName = "wsl-tcp-$Port"
    Remove-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue
    
    New-NetFirewallRule `
        -Name $RuleName `
        -DisplayName "WSL TCP $Port" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $Port `
        -Action Allow `
        -Profile Any | Out-Null
        
    Write-Host "Проброшен порт ${Port} -> ${wslIp}:${Port}"
}