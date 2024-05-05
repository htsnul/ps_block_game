Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$bmp = [Drawing.Bitmap]::new(32, 32)
$bmpScale = 16
$imageData = [byte[]]::new($bmp.Width * $bmp.Height * 4)

function ClearImageData($r, $g, $b) {
  for ($i = 0; $i -lt $imageData.Length; $i += 4) {
    $imageData[$i + 0] = $b
    $imageData[$i + 1] = $g
    $imageData[$i + 2] = $r
    $imageData[$i + 3] = 255
  }
}

function SetPixelToImageData($x, $y, $r, $g, $b) {
  $i = ($y * $bmp.Width + $x) * 4
  $imageData[$i + 0] = $b
  $imageData[$i + 1] = $g
  $imageData[$i + 2] = $r
  $imageData[$i + 3] = 255
}

function DrawImageData($graphics) {
  $bmpData = $bmp.LockBits(
    [Drawing.Rectangle]::new(0, 0, $bmp.Width, $bmp.Height),
    [Drawing.Imaging.ImageLockMode]::WriteOnly,
    $bmp.PixelFormat
  )
  $ptr = $bmpData.Scan0
  $bytes = [Math]::Abs($bmpData.Stride) * $bmp.Height
  [Runtime.InteropServices.Marshal]::Copy($imageData, 0, $ptr, $bytes)
  $bmp.UnlockBits($bmpData)
  $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
  $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
  $graphics.DrawImage($bmp, 0, 0, $bmp.Width * $bmpScale, $bmp.Height * $bmpScale)
}

$keys = [int[]]::new(256)
$keyCounts = [int[]]::new(256)

function ShowForm() {
  $form = [Windows.Forms.Form]::new()
  $form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedDialog
  $form.Text = 'Game'
  $form.ClientSize = [Drawing.Size]::new($bmp.Width * $bmpScale, $bmp.Height * $bmpScale)
  $form.StartPosition = 'CenterScreen'
  $form.Topmost = $true
  [System.Windows.Forms.Form].GetMethod('SetStyle',
    [Reflection.BindingFlags]::NonPublic -bor
    [Reflection.BindingFlags]::Instance
  ).Invoke($form, @(
    [Windows.Forms.ControlStyles]::DoubleBuffer -bor
    [Windows.Forms.ControlStyles]::AllPaintingInWmPaint
    $true
  ))
  $form.Add_KeyDown({ param ($sender, $event); $keys[$event.KeyValue] = 1 })
  $form.Add_KeyUp({ param ($sender, $event); $keys[$event.KeyValue] = 0 })
  $form.Add_Paint({ param ($sender, $event); Update $event.Graphics })
  $timer = [Windows.Forms.Timer]::new()
  $timer.Interval = 100
  $timer.Add_Tick({ $form.Invalidate($true) })
  $timer.Start()
  $form.ShowDialog()
}

$fieldW = 12
$fieldH = 22
$field = [int[]]::new($fieldW * $fieldH)

function ResetField() {
  for ($i = 0; $i -lt $fieldW * $fieldH; ++$i) {
    $x = $i % $fieldW
    $y = [Math]::Floor($i / $fieldW)
    $field[$i] = if (
      ($x -eq 0 -or $x -eq $fieldW - 1) -or
      ($y -eq 0 -or $y -eq $fieldH - 1)
    ) { 1 } else { 0 }
  }
}

function FieldIsBlock($x, $y) {
  if ($x -lt 0 -or $fieldW -le $x) { return $true }
  if ($y -lt 0 -or $fieldH -le $y) { return $true }
  $field[$y * $fieldW + $x]
}

function BlockHitsField($blockX, $blockY, $blockData) {
  for ($i = 0; $i -lt $blockW * $blockH; ++$i) {
    if (!$blockData[$i]) { continue }
    $lx = $i % $blockW
    $ly = [Math]::Floor($i / $blockW)
    $x = $blockX - $blockW / 2 + $lx
    $y = $blockY - $blockH / 2 + $ly
    if (FieldIsBlock $x $y) {
      return $true
    }
  }
}

function SetField($x, $y, $v) {
  $field[$y * $fieldW + $x] = $v
}

function SetCurrentBlockToField {
  for ($i = 0; $i -lt $blockW * $blockH; ++$i) {
    if (!$currentBlock.data[$i]) { continue }
    $lx = $i % $blockW
    $ly = [Math]::Floor($i / $blockW)
    $x = $currentBlock.x - $blockW / 2 + $lx
    $y = $currentBlock.y - $blockH / 2 + $ly
    SetField $x $y 1
  }
}

function EraseFilledFieldLine {
  for ($y = $fieldH - 2; $y -gt 0; $y--) {
    $isFilledLine = $true
    for ($x = 0; $x -le $fieldW; ++$x) {
      if (!(FieldIsBlock $x $y)) {
        $isFilledLine = $false
        break
      }
    }
    if (!$isFilledLine) { continue }
    $global:score++
    for ($dy = $y; $dy -gt 0; $dy--) {
      $sy = $dy - 1
      for ($x = 0; $x -le $fieldW; ++$x) {
        SetField $x $dy (FieldIsBlock $x $sy)
      }
    }
    for ($x = 1; $x -lt $fieldW - 1; ++$x) {
      SetField $x 1 0
    }
  }
}

function DrawFieldBlock($x, $y, $r, $g, $b) {
  $ox = $bmp.Width / 2 - $fieldW / 2
  $oy = $bmp.Height / 2 - $fieldH / 2
  SetPixelToImageData ($ox + $x) ($oy + $y) $r $g $b
}

function DrawField() {
  for ($i = 0; $i -lt $fieldW * $fieldH; ++$i) {
    $x = $i % $fieldW
    $y = [Math]::Floor($i / $fieldW)
    if ($field[$i]) {
      DrawFieldBlock $x $y 255 255 255
    }
  }
  for ($ly = 0; $ly -lt $blockH; ++$ly) {
    for ($lx = 0; $lx -lt $blockW; ++$lx) {
      $x = $currentBlock.x - $blockW / 2 + $lx
      $y = $currentBlock.y - $blockH / 2 + $ly
      if ($currentBlock.data[$ly * $blockW + $lx]) {
        DrawFieldBlock $x $y 128 128 128
        continue
      }
      if (!(FieldIsBlock $x $y)) {
        DrawFieldBlock $x $y 32 32 32
      }
    }
  }
}

$blockW = 4
$blockH = 4
$currentBlock = @{
  x = $fieldW / 2
  y = 1 + $blockH
  data = [int[]]::new($blockW * $blockH)
}
$score = 0

function ResetCurrentBlock() {
  $currentBlock.x = $fieldW / 2
  $currentBlock.y = 1 + $blockH / 2
  for ($i = 0; $i -lt $blockW * $blockH; ++$i) { $currentBlock.data[$i] = 0 }
  $currentBlock.data[(Get-Random -Maximum ($blockW * $blockH))] = 1
  for ($i = 0; $i -lt $blockW * $blockH; ++$i) {
    if ((Get-Random -Maximum 4) -eq 0) { $currentBlock.data[$i] = 1 }
  }
}

function GetRotatedBlockData($data, [int]$sign) {
  $newData = [int[]]::new($blockW * $blockH)
  if ($sign -lt 0) {
    for ($i = 0; $i -lt $blockW * $blockH; ++$i) {
      $lx = $i % $blockW
      $ly = [Math]::Floor($i / $blockW)
      $newData[$i] = $data[$lx * $blockW + ($blockH - 1 - $ly)]
    }
  } else {
    for ($i = 0; $i -lt $blockW * $blockH; ++$i) {
      $lx = $i % $blockW
      $ly = [Math]::Floor($i / $blockW)
      $newData[$i] = $data[($blockW - 1 - $lx) * $blockW + $ly]
    }
  }
  $newData
}

ResetField
ResetCurrentBlock

function DrawScore {
  for ($i = 0; $i -lt $score; ++$i) {
    SetPixelToImageData (1 + 2 * $i) 1 255 255 255
  }
}

function Update($graphics) {
  for ($i = 0; $i -lt 256; ++$i) {
    if ($keys[$i]) { $keyCounts[$i]++ } else { $keyCounts[$i] = 0 }
  }
  $provisionalX = $currentBlock.x
  if ($keys[[int][Windows.Forms.Keys]::Left]) { $provisionalX -= 1 }
  if ($keys[[int][Windows.Forms.Keys]::Right]) { $provisionalX += 1 }
  if (!(BlockHitsField $provisionalX $currentBlock.y $currentBlock.data)) {
    $currentBlock.x = $provisionalX
  }
  $provisionalY = $currentBlock.y
  if ($keys[[int][Windows.Forms.Keys]::Up]) { $provisionalY -= 1 }
  if ($keys[[int][Windows.Forms.Keys]::Down]) { $provisionalY += 1 }
  if (!(BlockHitsField $currentBlock.x $provisionalY $currentBlock.data)) {
    $currentBlock.y = $provisionalY
  }
  $provisionalBlockData = $currentBlock.data
  if ($keyCounts[[int][Windows.Forms.Keys]::Z] -eq 1) {
    $provisionalBlockData = GetRotatedBlockData $provisionalBlockData -1
  }
  if ($keyCounts[[int][Windows.Forms.Keys]::X] -eq 1) {
    $provisionalBlockData = GetRotatedBlockData $provisionalBlockData +1
  }
  if (!(BlockHitsField $currentBlock.x $currentBlock.y $provisionalBlockData)) {
    $currentBlock.data = $provisionalBlockData
  }
  if (
    $keys[[int][Windows.Forms.Keys]::C] -eq 1 -and
    (BlockHitsField $currentBlock.x ($currentBlock.y + 1) $currentBlock.data)
  ) {
    SetCurrentBlockToField
    EraseFilledFieldLine
    ResetCurrentBlock
    if (BlockHitsField $currentBlock.x $currentBlock.y $currentBlock.data) {
      ResetField
      ResetCurrentBlock
      $global:score = 0
    }
  }
  ClearImageData 0 0 0
  DrawField
  DrawScore
  DrawImageData $graphics
}

ShowForm
