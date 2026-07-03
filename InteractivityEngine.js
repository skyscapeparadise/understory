.pragma library

// ── Command registry ─────────────────────────────────────────────────────────
// Add new command types here — one registerCommand call, nothing else to change.
//
// Handler signature: function(it, context, state, itemIdx)
//   it      — the interactivity item object
//   context — { viewport, variablesModel, chapterPlayheadTime, activeChapterId,
//               elementType?, elementIdx? }
//   state   — mutable dispatch state { pendingJump, hasCueVideo }
//   itemIdx — this item's index within the fired list (identifies which cue,
//             combined with context.elementType/elementIdx, for level metering)

var _commands = {}

function registerCommand(name, handler) {
    _commands[name] = handler
}

// ── Built-in commands ─────────────────────────────────────────────────────────

registerCommand("video", function(it, context, state) {
    if (it.itemVideoTarget === "fill" && it.itemVideoPath) {
        context.viewport.playCueVideo(it.itemVideoPath)
        state.hasCueVideo = true
    }
})

registerCommand("sound", function(it, context, state, itemIdx) {
    if (!it.itemSoundPath) return
    var volume = it.itemSoundVolume !== undefined ? it.itemSoundVolume : 1.0
    var pan = it.itemSoundPan !== undefined ? it.itemSoundPan : 0.0
    var key = (context.elementType !== undefined && context.elementIdx !== undefined)
        ? (context.elementType + ":" + context.elementIdx + ":" + itemIdx) : ""
    context.viewport.playCueSound(it.itemSoundPath, volume, pan, key)
})

registerCommand("update", function(it, context) {
    if (!it.itemUpdateVar || !context.variablesModel) return
    var vm = context.variablesModel
    for (var j = 0; j < vm.count; j++) {
        var vrow = vm.get(j)
        if (vrow.varName !== it.itemUpdateVar) continue
        var newVal
        if (vrow.varType === "number") {
            var numCur   = parseFloat(vrow.varValue)  || 0
            var numDelta = parseFloat(it.itemUpdateVal) || 0
            if      (it.itemUpdateOp === "+") newVal = String(numCur + numDelta)
            else if (it.itemUpdateOp === "-") newVal = String(numCur - numDelta)
            else                              newVal = it.itemUpdateVal
        } else {
            newVal = it.itemUpdateVal
        }
        vm.setProperty(j, "varValue", newVal)
        break
    }
})

registerCommand("jump", function(it, context, state) {
    if (it.itemTargetSceneId >= 0 && !state.pendingJump)
        state.pendingJump = it
})

// ── Condition evaluation ──────────────────────────────────────────────────────

function evaluateIfCondition(it, context) {
    if (!it.itemConditionVar || !context.variablesModel) return false
    var vm = context.variablesModel
    for (var j = 0; j < vm.count; j++) {
        var vrow = vm.get(j)
        if (vrow.varName !== it.itemConditionVar) continue
        var cur  = vrow.varValue || ""
        var test = it.itemConditionVal || ""
        var op   = it.itemConditionOp  || "is"
        if (vrow.varType === "number") {
            var a = parseFloat(cur)  || 0
            var b = parseFloat(test) || 0
            if (op === ">")   return a > b
            if (op === "<")   return a < b
            if (op === "not") return a !== b
            return a === b
        } else {
            if (vrow.varType === "true or false" && test === "") test = "true"
            if (op === "not") return cur !== test
            return cur === test
        }
    }
    return false
}

function evaluateWhenCondition(it, context) {
    if (context.chapterPlayheadTime === undefined) return false
    var chapterId  = (it.itemWhenChapterId !== undefined) ? it.itemWhenChapterId : -1
    var op         = it.itemWhenOp || "="
    var targetSecs = (it.itemWhenSeconds   !== undefined) ? it.itemWhenSeconds   : 0
    if (chapterId >= 0 && context.activeChapterId !== chapterId) return false
    var cur = context.chapterPlayheadTime
    if (op === "<") return cur < targetSecs
    if (op === ">") return cur > targetSecs
    return Math.abs(cur - targetSecs) <= 3.0 / 25.0
}

// ── Main dispatch ─────────────────────────────────────────────────────────────
// trigger: "click" | "hover" | null (null = fire all items regardless of trigger)
// items:   array of interactivity item objects (already parsed from JSON)
// context: { viewport, variablesModel, chapterPlayheadTime?, activeChapterId? }

function fire(trigger, items, context) {
    var state = { pendingJump: null, hasCueVideo: false }
    var lastCondPassed = false

    for (var i = 0; i < items.length; i++) {
        var it = items[i]
        if (trigger !== null && it.itemTrigger !== trigger) continue

        var shouldExec = false
        if (it.itemAction === "cue") {
            shouldExec = true
        } else if (it.itemAction === "if") {
            lastCondPassed = evaluateIfCondition(it, context)
            shouldExec = lastCondPassed
        } else if (it.itemAction === "else") {
            shouldExec = !lastCondPassed
        } else if (it.itemAction === "where") {
            lastCondPassed = false
        } else if (it.itemAction === "when") {
            lastCondPassed = evaluateWhenCondition(it, context)
            shouldExec = lastCondPassed
        }

        if (!shouldExec) continue

        var handler = _commands[it.itemCommand]
        if (handler) handler(it, context, state, i)
    }

    if (state.pendingJump) {
        var pj = state.pendingJump
        var ms = Math.round((pj.itemTransitionSpeed || 1.0) * 1000)
        var soundMs = Math.round((pj.itemSoundSpeed !== undefined ? pj.itemSoundSpeed : (pj.itemTransitionSpeed || 1.0)) * 1000)
        if (state.hasCueVideo) context.viewport.cueVideoHasJump = true
        context.viewport.jumpToScene(
            pj.itemTargetSceneId,
            pj.itemTransition    || "cut",
            ms,
            pj.itemWipeFeather   || 0.0,
            pj.itemWipeDirection || "right",
            pj.itemPushDirection || "right",
            pj.itemLookYaw         !== undefined ? pj.itemLookYaw       : 90.0,
            pj.itemLookPitch       !== undefined ? pj.itemLookPitch     : 0.0,
            pj.itemLookFovMM       !== undefined ? pj.itemLookFovMM     : 24.0,
            pj.itemLookOvershoot   !== undefined ? pj.itemLookOvershoot : 1.0,
            pj.itemLookShutter     !== undefined ? pj.itemLookShutter   : 0.10,
            soundMs
        )
    }
}
