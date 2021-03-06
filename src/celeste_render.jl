include("drawing.jl")
include("layers.jl")
include("auto_tiler.jl")
include("decals.jl")
include("entities.jl")
include("triggers.jl")

function drawTile(ctx::Cairo.CairoContext, x::Integer, y::Integer, tiles::Tiles, meta::TilerMeta, states::TileStates; alpha::Number=getGlobalAlpha())
    tileValue = tiles.data[y, x]

    if tileValue != '0'
        imagePath = meta.paths[tileValue]
        quads = getMaskQuads(x, y, tiles, meta)

        quadX, quadY = quads[Integer(mod1(states.rands[y, x], length(quads)))]
        drawX, drawY = (x - 1) * 8, (y - 1) * 8

        if tileValue != states.chars[y, x] || state.quads[y, x] != (quadX, quadY)
            drawImage(ctx, imagePath, drawX, drawY, quadX * 8, quadY * 8, 8, 8, alpha=alpha)

            states.quads[y, x] = (quadX, quadY)
        end
    end
end

function drawTiles(ctx::Cairo.CairoContext, tiles::Tiles, meta::TilerMeta, states::TileStates, width::Integer, height::Integer; alpha::Number=getGlobalAlpha())
    for y in 1:height, x in 1:width
        drawTile(ctx, x, y, tiles, meta, states, alpha=alpha)
    end
end

function drawTiles(ctx::Cairo.CairoContext, dr::DrawableRoom, fg::Bool=true; alpha::Number=getGlobalAlpha())
    tiles = fg? dr.room.fgTiles : dr.room.bgTiles
    height, width = size(tiles.data)

    states = fg? dr.fgTileStates : dr.bgTileStates
    meta = fg? fgTilerMeta : bgTilerMeta

    if size(states) != (height, width)
        updateTileStates!(dr.room, dr.map.package, states, width, height, fg)
    end

    drawTiles(ctx, tiles, meta, states, width, height, alpha=alpha)

    return true
end

drawTiles(layer::Layer, dr::DrawableRoom, fg::Bool=true; alpha::Number=getGlobalAlpha()) = drawTiles(creategc(layer.surface), dr, fg, alpha=alpha)

function drawParallax(ctx::Cairo.CairoContext, parallax::Maple.Parallax, camera::Camera, fg::Bool=true)

end

function drawApply(ctx::Cairo.CairoContext, apply::Maple.Apply, camera::Camera, fg::Bool=true)

end

function drawEffect(ctx::Cairo.CairoContext, effect::Maple.Effect, camera::Camera, fg::Bool=true)

end

backgroundFuncs = Dict{Type, Function}(
    Maple.Parallax => drawParallax,
    Maple.Apply => drawApply,
    Maple.Effect => drawEffect,
)

function drawBackground(layer::Layer, dr::DrawableRoom, camera::Camera, fg::Bool=true)
    styles = fg? dr.map.style.foregrounds : dr.map.style.backgrounds
    ctx = creategc(layer.surface)

    if !fg
        paintSurface(ctx, dr.fillColor)
    end

    for style in styles.children
        t = typeof(style)

        if haskey(backgroundFuncs, t)
            backgroundFuncs[t](ctx, style, camera, fg)
        end
    end
end

function drawDecals(layer::Layer, dr::DrawableRoom, fg::Bool=true)
    ctx = creategc(layer.surface)
    decals = fg? dr.room.fgDecals : dr.room.bgDecals

    for decal in decals
        drawDecal(ctx, decal)
    end

    return true
end

function drawEntities(layer::Layer, dr::DrawableRoom)
    ctx = creategc(layer.surface)
    entities = dr.room.entities
    
    for entity in entities
        renderEntity(ctx, layer, entity, dr.room)
    end

    return true
end

function drawTriggers(layer::Layer, dr::DrawableRoom)
    ctx = creategc(layer.surface)
    triggers = dr.room.triggers
    
    for trigger in triggers
        renderTrigger(ctx, layer, trigger, dr.room)
    end

    return true
end

function resetDrawingSettings()
    reset!(camera)
end

loadExternalSprites!()

drawingLayers = nothing
drawableRooms = Dict{Map, Dict{Room, DrawableRoom}}()

redrawingFuncs["fgDecals"] = (layer, room) -> drawDecals(layer, room, true)
redrawingFuncs["bgDecals"] = (layer, room) -> drawDecals(layer, room, false)

redrawingFuncs["fgTiles"] = (layer, room) -> drawTiles(layer, room, true)
redrawingFuncs["bgTiles"] = (layer, room) -> drawTiles(layer, room, false)

redrawingFuncs["fgParallax"] = (layer, room, camera) -> drawBackground(layer, room, camera, true)
redrawingFuncs["bgParallax"] = (layer, room, camera) -> drawBackground(layer, room, camera, false)

redrawingFuncs["entities"] = drawEntities
redrawingFuncs["triggers"] = drawTriggers

function getDrawableRooms(map::Map)
    if !haskey(drawableRooms, map)
        drawableRooms[map] = Dict{Room, DrawableRoom}()
    end

    return collect(values(drawableRooms[map]))
end

function getDrawableRoom(map::Map, room::Room)
    if !haskey(drawableRooms, map)
        drawableRooms[map] = Dict{Room, DrawableRoom}()
    end

    if !haskey(drawableRooms[map], room)
        drawableRooms[map][room] = DrawableRoom(map, room)
    end

    return drawableRooms[map][room]
end

function deleteDrawableRoomCache(map::Map)
    rooms = getDrawableRooms(map)
    for room in rooms
        destroy(room)
    end

    delete!(drawableRooms, map)
end

function updateDrawingLayers!(map::Map, room::Room)
    global drawingLayers = getDrawableRoom(map, room).layers
end

function drawMap(ctx::Cairo.CairoContext, camera::Camera, map::Map; adjacentAlpha::Number=colors.adjacent_room_alpha, backgroundFill::colorTupleType=colors.background_canvas_fill)
    width, height = floor(Int, ctx.surface.width), floor(Int, ctx.surface.height)

    paintSurface(ctx, backgroundFill)
    pattern_set_filter(get_source(ctx), Cairo.FILTER_NEAREST)

    for room in map.rooms
        dr = getDrawableRoom(map, room)
        if roomVisible(camera, width, height, room)
            alpha = loadedState.roomName == room.name? 1.0 : adjacentAlpha
            drawRoom(ctx, camera, dr, alpha=alpha)
        end
    end
end

drawMap(canvas::Gtk.GtkCanvas, camera::Camera, map::Map) = drawMap(Gtk.getgc(canvas), camera, map)

function drawRoom(ctx::Cairo.CairoContext, camera::Camera, room::DrawableRoom; alpha::Number=getGlobalAlpha())
    renderingLayer = room.rendering
    drawingLayers = room.layers

    renderingLayer.redraw = redrawRenderingLayer(renderingLayer, drawingLayers)

    if renderingLayer.redraw
        resetLayer!(renderingLayer, room)
        renderingCtx = creategc(renderingLayer.surface)

        renderingLayer.redraw = false
        combineLayers!(renderingCtx, drawingLayers, camera, room)
    end

    Cairo.save(ctx)

    translate(ctx, -camera.x, -camera.y)
    scale(ctx, camera.scale, camera.scale)
    translate(ctx, room.room.position...)

    applyLayer!(ctx, renderingLayer, alpha=alpha)

    restore(ctx)
end