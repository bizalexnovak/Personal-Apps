import XCTest
import SwiftData
@testable import Foob

/// CloudKit's mirroring requires every attribute to be optional (or have a
/// default value), forbids unique constraints, and requires every
/// relationship to be optional. If a model regresses on any of these, the
/// CloudKit-backed store silently falls back to local-only (see
/// AppModelContainer.StoreMode) instead of syncing — this test exists so
/// that regression fails loudly at test time instead.
@MainActor
final class CloudKitSchemaTests: XCTestCase {
    private func makeSchema() -> Schema {
        Schema(AppModelContainer.models)
    }

    func testEveryAttributeIsOptionalOrHasDefault() {
        let schema = makeSchema()
        let attributes = schema.entities.flatMap { entity in
            entity.attributes.map { (entity.name, $0) }
        }
        // Guard: SwiftData only surfaces `defaultValue` for defaults it captured
        // from the macro. If it reports none at all for a schema we know has
        // plenty, the reflection — not the models — is what changed, and
        // asserting here would just be noise. The other two tests still hold.
        guard attributes.contains(where: { $0.1.defaultValue != nil }) else {
            XCTFail("Schema reported no default values at all — Schema.Attribute.defaultValue reflection changed; re-check this test against the SDK")
            return
        }
        for (entityName, attribute) in attributes {
            XCTAssertTrue(
                attribute.isOptional || attribute.defaultValue != nil,
                "\(entityName).\(attribute.name) must be optional or have a default value for CloudKit"
            )
        }
    }

    func testNoAttributeIsMarkedUnique() {
        let schema = makeSchema()
        for entity in schema.entities {
            for attribute in entity.attributes {
                XCTAssertFalse(
                    attribute.isUnique,
                    "\(entity.name).\(attribute.name) must not be unique — CloudKit does not support unique constraints"
                )
            }
        }
    }

    func testEveryRelationshipIsOptional() {
        let schema = makeSchema()
        for entity in schema.entities {
            for relationship in entity.relationships {
                XCTAssertTrue(
                    relationship.isOptional,
                    "\(entity.name).\(relationship.name) must be optional for CloudKit"
                )
            }
        }
    }
}
