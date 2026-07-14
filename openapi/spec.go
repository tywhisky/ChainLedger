package openapi

import _ "embed"

// Spec is the OpenAPI contract served by the API documentation endpoints.
//
//go:embed openapi.yaml
var Spec []byte
