export type ActiveViewerResponse = {
	activeViewer: boolean,
}

-- The position batch POST body is not JSON — it's the raw packed buffer built by
-- position-collector.luau / position-packing.luau (see constants.luau for the
-- wire format). No Luau type describes a buffer's internal layout, so there's no
-- corresponding export type here.

return {}
