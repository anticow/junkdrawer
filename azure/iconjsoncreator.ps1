foreach ($icon in (ls 'C:\users\grife.COWGOMU\Downloads\x4icons\ICONOS TEXTO X4'))
{
    $iconName = [PSCustomObject]@{
        path = $icon.name
        name = $icon.name.split('.')[0]
        tags = "[ x4 ]"
    }
    [array]$iconArray += $iconName
}