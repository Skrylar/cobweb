
type
  Observer* [E] = object
  SinkProc* [E] = proc(event: E) {.closure.}

proc dispatch*[E] (observer: Observer[E]; event: E) =
  ## Sends an event to all subscribers of this observer.
  discard

proc sink*[E] (observer: Observer[E]): SinkProc[E] =
  ## Produces a sink closure. Calling this closure and
  ## providing an event is equivalent to calling dispatch
  ## on the observer itself.
  return proc(event: E) =
    observer.dispatch(event)

when isMainModule:
  import unittest

  test "Sinking":
    var o: Observer[string]
    var s = o.sink()
    s("boo!")

