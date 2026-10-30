# Swagger to Dart

**A Flutter desktop tool that turns a Swagger / OpenAPI spec into typed Dart request and response classes.**

When a backend ships an OpenAPI spec, writing the client models by hand is slow and error-prone: every field name, every nullable, every nested object. This tool reads the spec, lets you pick the endpoints you need, and generates code that drops straight into a Flutter project.

## How it works

1. **Load a spec** from a URL or a local JSON file.
2. **Pick endpoints** from the list (path, method, operationId).
3. Optionally set a **class prefix** (e.g. `Api` → `ApiCreateUserRequest`).
4. **Generate**, preview the code side by side, and **save** it into `requests/` and `responses/` folders.

## What it generates

**Request classes**
- One class per endpoint, extending your project's base request type
- An inner `Parameters` class for the body and query/path parameters
- `validate()` for required fields, called before the request is sent
- `toMap()` for serialization

**Response classes**
- `@JsonSerializable` classes with `@JsonKey(name: ...)` for the original field names
- `fromJson()` / `toJson()`
- Nested schemas (`$ref`) resolved into their own classes, nullable fields kept nullable

**Type mapping**

| OpenAPI | Dart |
|---|---|
| `string` | `String` |
| `integer` | `int` |
| `number` | `double` |
| `boolean` | `bool` |
| `array` | `List<T>` |
| `object` / `$ref` | generated class or `Map<String, dynamic>` |

Class names are derived from the `operationId` when there is one (`createUser` → `CreateUserRequest`) and from the path otherwise.

## Example

For a `POST /api/v1/loan/calculate` endpoint with `operationId: calculateLoan` and prefix `Api`:

```dart
import 'package:your_app/network/requests.dart';

class ApiLoanCalculationRequest extends JsonPostRequest {
  ApiLoanCalculationRequest(ApiLoanCalculationRequestParameters parameters)
      : super("/api/v1/loan/calculate", parameters.toMap()) {
    // Validate required fields before sending request
    parameters.validate();
  }
}
```

A sample spec is included in [`test_swagger.json`](test_swagger.json).

## Project layout

```
lib/
  main.dart                          two-pane UI: spec + endpoint list, code preview
  providers/swagger_provider.dart    state (provider)
  services/swagger_parser.dart       loads the spec, lists endpoints and schemas
  services/dart_model_generator.dart request/response code generation
  models/swagger_endpoint.dart
test/
  dart_model_generator_test.dart
```

## Run

```bash
flutter pub get
flutter run -d macos     # or windows / linux
flutter test
```

## Why I built it

I work on a large Flutter app that talks to many backend endpoints, each described by an OpenAPI spec. Generating the models instead of typing them makes integrating a new endpoint much faster and removes a whole class of typo bugs in field names.

---

Built by **Muhammed Ali Çınar**, senior Flutter & iOS developer.
