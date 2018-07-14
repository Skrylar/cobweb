
type
  EventType* = enum
    etInitial
    etNext
    etEnd
    etError

  SinkResult* = enum
    srMore   ## You can submit more events.
    srNoMore ## The stream is dead; you can't send more events.

  SinkProc* [E] = proc(value: E): SinkResult {.closure.}

  Event* [E] = object
    created_at*: int64
    case kind*: EventType
    of etInitial, etNext:
      value*: E
    of etError:
      error*: Exception
    of etEnd:
      discard

  HandlerResult* = enum
    hrMore   ## Remain subscribed.
    hrNoMore ## Remove me from your subscriptions.

  HandlerProc* [E] = proc(event: Event[E]): HandlerResult {.closure.}
  DoActionProc* [V] = proc(value: V) {.closure.}
  FilterEventProc* [E] = proc(event: Event[E]): bool {.closure.}
  FilterValueProc* [V] = proc(value: V): bool {.closure.}

  Observer* [E] = ref object
    dead: bool
    subscriptions: seq[HandlerProc[E]]

proc is_initial* [E](self: Event[E]): bool =
  return self.kind == etInitial

proc is_next* [E](self: Event[E]): bool =
  return self.kind == etNext

proc is_end* [E](self: Event[E]): bool =
  return self.kind == etEnd

proc is_error* [E](self: Event[E]): bool =
  return self.kind == etError

proc dispatch*[E] (observer: Observer[E]; event: Event[E]) =
  ## Sends an event to all subscribers of this observer.
  template subs: untyped = observer.subscriptions
  if subs == nil or subs.len < 1:
    # sanity check
    return

  # transmit the event
  var idx = 0
  while idx < subs.len:
    var s = subs[idx]
    case s(event)
    of hrMore:
      inc idx
    of hrNoMore:
      subs.delete(idx)

proc dispatch*[E] (observer: Observer[E]; value: E) =
  ## Sends an event to all subscribers of this observer.

  # construct the event
  var event: Event[E]
  event.kind = etNext
  event.created_at = 0 # TODO get current system time
  event.value = value

  observer.dispatch(event)

method on_subscription*[E] (observer: Observer[E]; fn: HandlerProc) {.base.} =
  ## Default observers don't react to new subscriptions.
  discard

proc subscribe*[E] (observer: Observer[E]; handler: HandlerProc[E]) =
  ## Attaches a new handler to an existing observable. It
  ## will receive the raw event object for inspection.
  assert(handler != nil) # sanity test
  if observer.subscriptions == nil:
    # more sanity problems
    new_seq(observer.subscriptions, 0)

  observer.subscriptions.add(handler)
  on_subscription(observer, handler) # some streams care about this

proc sink*[E] (observer: Observer[E]): SinkProc[E] =
  ## Produces a sink closure. Calling this closure and
  ## providing an event is equivalent to calling dispatch
  ## on the observer itself.
  return proc(value: E): SinkResult =
    if observer.dead:
      return srNoMore
    else:
      observer.dispatch(value)
      if observer.dead:
        return srNoMore
      else:
        return srMore

proc do_action*[E] (observer: Observer[E]; fn: DoActionProc[E]) =
  observer.subscribe(proc (event: E): HandlerResult =
    if event.is_next:
      fn(event.value)
    return hrMore)

proc keep*[E] (observer: Observer[E]; fn: FilterEventProc[E]): Observer[E] =
  var output = new(Observer[E])
  observer.subscribe(proc (event: Event[E]): HandlerProc =
    if event.is_next == true and fn(event) == true:
      output.dispatch(event))
  return output

proc keep*[E] (observer: Observer[E]; fn: FilterValueProc[E]) =
  var output = new(Observer[E])
  observer.subscribe(proc (event: Event[E]): HandlerProc =
    if event.is_next == true and fn(event.value) == true:
      output.dispatch(event))
  return output

proc drop*[E] (observer: Observer[E]; fn: FilterEventProc[E]): Observer[E] =
  var output = new(Observer[E])
  observer.subscribe(proc (event: Event[E]): HandlerProc =
    if event.is_next == true and fn(event) == false:
      output.dispatch(event))
  return output

proc drop*[E] (observer: Observer[E]; fn: FilterValueProc[E]) =
  var output = new(Observer[E])
  observer.subscribe(proc (event: Event[E]): HandlerProc =
    if event.is_next == true and fn(event.value) == false:
      output.dispatch(event))
  return output

when isMainModule:
  import unittest

  test "Sinking":
    var o = new(Observer[string])
    var target = false
    o.subscribe(proc (event: Event[string]): HandlerResult =
      target = true
      return hrMore)
    var s = o.sink()
    check s("boo!") == srMore
    check target == true

