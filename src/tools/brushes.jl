module Brushes

using ..Ahorn

displayName = "Brushes"
group = "Brushes"

drawingLayers = Ahorn.Layer[]

toolsLayer = nothing
targetLayer = nothing
material = '0'

brushes = Ahorn.Brush[
    Ahorn.Brush(
        "Pencil",
        hcat(1)
    ),

    Ahorn.Brush(
        "Dither",
        [
            1 0;
            0 1
        ]
    ),
    Ahorn.Brush(
        "Ahorn",
        [
            0 0 1 0 0 0 0;
            0 1 0 1 0 0 0;
            0 0 0 1 1 0 1;
            0 0 1 1 1 0 0;
            0 1 1 1 1 1 0;
            0 1 1 1 1 1 0;
            1 1 1 1 1 1 0;
            1 1 1 1 1 0 0;
            0 1 1 1 0 0 0;
        ]
    )
]

selectedBrush = brushes[1]

hoveringBrush = nothing
phantomBrushes = Dict{Tuple{Integer, Integer}, Ahorn.Brush}()

function drawBrushes(layer::Ahorn.Layer, room::Ahorn.Maple.Room)
    if !isa(hoveringBrush, Void)
        x, y, brush = hoveringBrush

        Ahorn.drawBrush(brush, layer, x, y)
    end

    for (pos, brush) in phantomBrushes
         x, y = pos

         Ahorn.drawBrush(brush, layer, x, y)
    end
end

function cleanup()
    global hoveringBrush = nothing
    empty!(phantomBrushes)

    Ahorn.redrawLayer!(toolsLayer)
end

function setMaterials!(layer::Ahorn.Layer)
    validTiles = Ahorn.validTiles(layer)
    tileNames = Ahorn.tileNames(layer)

    Ahorn.setMaterialList!([tileNames[mat] for mat in validTiles], row -> row[1] == tileNames[material])
end

function mouseMotion(x::Number, y::Number)
    global hoveringBrush = (x, y, deepcopy(selectedBrush))

    Ahorn.redrawLayer!(toolsLayer)
end

function middleClick(x::Number, y::Number)
    tiles = Ahorn.roomTiles(targetLayer, Ahorn.loadedState.room)
    tileNames = Ahorn.tileNames(targetLayer)
    target = get(tiles.data, (y, x), '0')

    global material = target
    layerName = Ahorn.layerName(targetLayer)
    Ahorn.persistence["brushes_material_$(layerName)"] = material
    Ahorn.selectMaterialList!(tileNames[target])
end

function leftClick(x::Number, y::Number)
    layer = Ahorn.layerName(targetLayer)
    Ahorn.History.addSnapshot!(Ahorn.History.RoomSnapshot("Brush $(selectedBrush.name)", Ahorn.loadedState.room))

    roomTiles = Ahorn.roomTiles(targetLayer, Ahorn.loadedState.room)
    Ahorn.applyBrush!(selectedBrush, roomTiles, material, x, y)

    Ahorn.redrawLayer!(targetLayer)
end

function selectionMotion(x1::Number, y1::Number, x2::Number, y2::Number)
    box, boy = selectedBrush.offset

    startX = x1
    startY = y1
    
    pixels = rotr90(selectedBrush.pixels, selectedBrush.rotation)

    bh, bw = size(pixels)
    ox, oy = mod(startX, bw), mod(startY, bh)

    bx, by = div(x2, bw) * bw + ox - box + 1, div(y2, bh) * bh + oy - boy + 1

    if !haskey(phantomBrushes, (bx, by)) 
        phantomBrushes[(bx, by)] = deepcopy(selectedBrush)

        Ahorn.redrawLayer!(toolsLayer)
    end
end

function selectionFinish(rect::Ahorn.Rectangle)
    if !isempty(phantomBrushes)
        Ahorn.History.addSnapshot!(Ahorn.History.RoomSnapshot("Brush ($(selectedBrush.name), $material)", Ahorn.loadedState.room))    
    end

    for (pos, brush) in phantomBrushes
        x, y = pos

        roomTiles = Ahorn.roomTiles(targetLayer, Ahorn.loadedState.room)
        Ahorn.applyBrush!(brush, roomTiles, material, x, y)
    end

    if !isempty(phantomBrushes)
        empty!(phantomBrushes)

        Ahorn.redrawLayer!(targetLayer)
    end

    Ahorn.redrawLayer!(toolsLayer)
end

function toolSelected(subTools::Ahorn.ListContainer, layers::Ahorn.ListContainer, materials::Ahorn.ListContainer)
    layerName = Ahorn.layerName(targetLayer)
    tileNames = Ahorn.tileNames(targetLayer)
    global material = get(Ahorn.persistence, "brushes_material_$(layerName)", tileNames["Air"])[1]

    wantedBrush = get(Ahorn.persistence, "brushes_brushes_brush", brushes[1].name)
    Ahorn.updateTreeView!(subTools, [brush.name for brush in brushes], row -> row[1] == wantedBrush)

    wantedLayer = get(Ahorn.persistence, "brushes_layer", "fgTiles")
    Ahorn.updateLayerList!(["fgTiles", "bgTiles"], row -> row[1] == wantedLayer)

    Ahorn.redrawingFuncs["tools"] = drawBrushes
    Ahorn.redrawLayer!(toolsLayer)
end

function layerSelected(list::Ahorn.ListContainer, materials::Ahorn.ListContainer, selected::String)
    global targetLayer = Ahorn.getLayerByName(drawingLayers, selected)
    Ahorn.persistence["brushes_layer"] = selected

    tileNames = Ahorn.tileNames(targetLayer)
    layerName = Ahorn.layerName(targetLayer)
    global material = get(Ahorn.persistence, "brushes_material_$(layerName)", tileNames["Air"])[1]
    setMaterials!(targetLayer)
end

function materialSelected(list::Ahorn.ListContainer, selected::String)
    tileNames = Ahorn.tileNames(targetLayer)
    layerName = Ahorn.layerName(targetLayer)
    Ahorn.persistence["brushes_material_$(layerName)"] = tileNames[selected]
    global material = tileNames[selected]
end

function layersChanged(layers::Array{Ahorn.Layer, 1})
    wantedLayer = get(Ahorn.persistence, "brushes_layer", "fgTiles")

    global drawingLayers = layers
    global toolsLayer = Ahorn.getLayerByName(layers, "tools")
    global targetLayer = Ahorn.selectLayer!(layers, wantedLayer, "fgTiles")
end

function subToolSelected(list::Ahorn.ListContainer, selected::String)
    for brush in brushes
        if brush.name == selected
            Ahorn.persistence["brushes_brushes_brush"] = selected
            global selectedBrush = brush
        end
    end
end

function keyboard(event::Ahorn.eventKey)
    shouldRedraw = false

    if event.keyval == Ahorn.keyval("l")
        selectedBrush.rotation = mod(selectedBrush.rotation + 1, 4)

        shouldRedraw |= true

    elseif event.keyval == Ahorn.keyval("r")
        selectedBrush.rotation = mod(selectedBrush.rotation - 1, 4)

        shouldRedraw |= true
    end

    if shouldRedraw && hoveringBrush !== nothing
        global hoveringBrush = (hoveringBrush[1], hoveringBrush[2], deepcopy(selectedBrush))

        Ahorn.redrawLayer!(toolsLayer)
    end
end

end