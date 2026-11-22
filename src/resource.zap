import attributes as attr
import resource_environment as environment
import semconv

interface Resource:
    def attributes(self) -> dict[str, attr.AttributeValue]
    def schema_url(self) -> str
    def merge(self, Resource other) -> Resource

struct _Resource:
    dict[str, attr.AttributeValue] _attributes
    str _schema_url

    def attributes(self) -> dict[str, attr.AttributeValue]:
        "Return a snapshot of the attributes, including array values."
        dict[str, attr.AttributeValue] copied = {}
        _copy_attributes(copied, self._attributes)
        return copied

    def schema_url(self) -> str:
        "Return the schema URL, or an empty string when unspecified."
        return self._schema_url

    def merge(self, Resource other) -> Resource:
        "Merge resources with values from other taking precedence."
        auto other_schema = other.schema_url()
        if self._schema_url != "" and other_schema != "" and self._schema_url != other_schema:
            logging.warning(
                "cannot merge OpenTelemetry resources with different schema URLs",
            )
            return self
        str merged_schema = self._schema_url
        if merged_schema == "":
            merged_schema = other_schema
        auto combined = self.attributes()
        _copy_attributes(combined, other.attributes())
        return _Resource(combined, merged_schema)

def _copy_attributes(
    dict[str, attr.AttributeValue] destination,
    dict[str, attr.AttributeValue] source,
):
    for key, value in source.items():
        if key.strip() == "":
            raise ValueError("OpenTelemetry resource attribute key must not be empty")
        destination[key] = value.snapshot()

def create(
    dict[str, attr.AttributeValue] attributes = {},
    str schema_url = "",
) -> Resource:
    "Create a resource using SDK defaults, environment overrides, and explicit attributes."
    dict[str, attr.AttributeValue] combined = {
        semconv.SERVICE_NAME: attr.AttributeValue.Str("unknown_service"),
        semconv.TELEMETRY_SDK_NAME: attr.AttributeValue.Str("opentelemetry"),
        semconv.TELEMETRY_SDK_LANGUAGE: attr.AttributeValue.Str("zap"),
        semconv.TELEMETRY_SDK_VERSION: attr.AttributeValue.Str("0.1.0"),
    }
    try:
        auto detected = environment.parse_resource_attributes(
            os.getenv("OTEL_RESOURCE_ATTRIBUTES"),
        )
        for key, value in detected.items():
            combined[key] = attr.AttributeValue.Str(value)
    except ValueError:
        logging.warning("ignoring malformed OTEL_RESOURCE_ATTRIBUTES")
    auto service_name = os.getenv("OTEL_SERVICE_NAME")
    if service_name != "":
        combined[semconv.SERVICE_NAME] = attr.AttributeValue.Str(service_name)
    _copy_attributes(combined, attributes)
    return _Resource(combined, schema_url)
