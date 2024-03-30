import 'dart:io';
import 'dart:convert';
import 'package:jinja/jinja.dart' as jj;
import 'package:apidash/consts.dart';
import 'package:apidash/utils/utils.dart'
    show getNewUuid, getValidRequestUri, padMultilineString, stripUriParams;
import 'package:apidash/models/models.dart' show RequestModel;

class JuliaHttpClientCodeGen {
  final String kTemplateStart = """
using HTTP{% if hasJson %}, JSON{% endif %}
\n
""";

  final String kTemplateUrl = """
url = "{{url}}"
\n
""";
  final String kTemplateBoundary = """
boundary = "{{boundary}}"
\n
""";

  String kTemplateParams = """
params = Dict(
{%- for name, value in params %}
    "{{ name }}" => "{{ value }}",
{%- endfor %}
)
\n
""";

  String kTemplateHeaders = """
headers = Dict(
{%- for name, value in headers %}
    "{{ name }}" => "{{ value }}",
{%- endfor %}
)
\n
""";

  final String kTemplateFormDataBody = '''
{{ 'data' if hasFile else 'payload' }} = Dict(
{%- for data in formdata %}
{%- if data.type == "text" %}
    "{{ data.name }}" => "{{ data.value }}",
{%- else %}
    "{{ data.name }}" => open("{{ data.value }}"),
{%- endif %}
{%- endfor %}
)
{%- if hasFile %}

payload = HTTP.Form(data{% if boundary is defined %}, boundary=boundary{% endif %})
{%- endif %}
\n
''';

  String kTemplateBody = """
payload = \"\"\"{{ body }}\"\"\"
\n
""";

  String kTemplateRequest = """
response = HTTP.request("{{ method | upper }}", url
""";

  String kStringRequestParams = """, query=params""";

  String kStringRequestBody = """, payload=payload""";

  String kStringRequestJson = """, JSON.json(payload)""";

  String kStringRequestHeaders = """, headers=headers""";

  final String kStringRequestEnd = """
)

println("Status Code:", response.status)
println("Response Body:", String(response.body))
""";

  String? getCode(RequestModel requestModel) {
    try {
      String result = "";
      bool hasQuery = false;
      bool hasHeaders = false;
      bool hasBody = false;
      bool hasJsonBody = false;
      String uuid = getNewUuid();

      var rec = getValidRequestUri(
        requestModel.url,
        requestModel.enabledRequestParams,
      );
      Uri? uri = rec.$1;
      if (uri != null) {
        var templateStartUrl = jj.Template(kTemplateStart);
        result += templateStartUrl.render({
          "url": stripUriParams(uri),
        });

        if (uri.hasQuery) {
          var params = uri.queryParameters;
          if (params.isNotEmpty) {
            hasQuery = true;
            var templateParams = jj.Template(kTemplateParams);
            var paramsString = kEncoder.convert(params);
            paramsString = padMultilineString(paramsString, kParamsPadding);
            result += templateParams.render({"params": paramsString});
          }
        }

        if (requestModel.hasJsonData) {
          hasJsonBody = true;
          var templateBody = jj.Template(kTemplateJson);
          result += templateBody.render({"body": requestModel.requestBody});
        } else if (requestModel.hasTextData) {
          hasBody = true;
          var templateBody = jj.Template(kTemplateBody);
          result += templateBody.render({"body": requestModel.requestBody});
        }

        var headersList = requestModel.enabledRequestHeaders;
        if (headersList != null || hasBody) {
          var headers = requestModel.enabledHeadersMap;
          if (requestModel.hasFormData) {
            var formHeaderTemplate =
                jj.Template(kTemplateFormHeaderContentType);
            headers[HttpHeaders.contentTypeHeader] = formHeaderTemplate.render({
              "boundary": uuid,
            });
          }
          if (headers.isNotEmpty || hasBody) {
            hasHeaders = true;
            if (hasBody) {
              headers[HttpHeaders.contentTypeHeader] =
                  requestModel.requestBodyContentType.header;
            }
            var headersString = kEncoder.convert(headers);
            headersString = padMultilineString(headersString, kHeadersPadding);
            var templateHeaders = jj.Template(kTemplateHeaders);
            result += templateHeaders.render({"headers": headersString});
          }
        }
        if (requestModel.hasFormData) {
          var formDataBodyData = jj.Template(kStringFormDataBody);
          result += formDataBodyData.render(
            {
              "fields_list": json.encode(requestModel.formDataMapList),
              "boundary": uuid,
            },
          );
        }
        var templateRequest = jj.Template(kTemplateRequest);
        result += templateRequest.render({
          "method": requestModel.method.name.toLowerCase(),
        });

        if (hasQuery) {
          result += kStringRequestParams;
        }

        if (hasBody || requestModel.hasFormData) {
          result += kStringRequestBody;
        }

        if (hasJsonBody || requestModel.hasFormData) {
          result += kStringRequestJson;
        }

        if (hasHeaders || requestModel.hasFormData) {
          result += kStringRequestHeaders;
        }

        result += kStringRequestEnd;
      }
      return result;
    } catch (e) {
      return null;
    }
  }
}
