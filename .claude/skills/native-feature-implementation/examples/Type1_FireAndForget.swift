// Type 1 — Fire and forget
// Use when: native API returns Void, no nativeToHybrid contract file.
// Example: onCardsSectionUnLoaded, cardDelivered
// RULE: identifier is Optional<String> — use guard let + logAppIdentifierFetchFailed on failure.

@objc public func <methodName>(_ payload: [String: Any]) {
    guard
        let identifier = MoEngagePluginUtils.fetchIdentifierFromPayload(attribute: payload)
    else {
        logAppIdentifierFetchFailed(for: payload)
        return
    }
    MoEngagePluginCardsLogger.debug("<MethodName> - ", forData: payload)
    handler.<nativeMethod>(forAppID: identifier)
}

// Real example — onCardsSectionUnLoaded
@objc public func onCardsSectionUnLoaded(_ accountData: [String: Any]) {
    guard
        let identifier = MoEngagePluginUtils.fetchIdentifierFromPayload(attribute: accountData)
    else {
        logAppIdentifierFetchFailed(for: accountData)
        return
    }
    MoEngagePluginCardsLogger.debug("Card Section Unloaded - ", forData: accountData)
    handler.cardsViewControllerDismissed(forAppID: identifier)
}

// Real example — cardDelivered
@objc public func cardDelivered(_ accountData: [String: Any]) {
    guard
        let identifier = MoEngagePluginUtils.fetchIdentifierFromPayload(attribute: accountData)
    else {
        logAppIdentifierFetchFailed(for: accountData)
        return
    }
    MoEngagePluginCardsLogger.debug("Card Delivered - ", forData: accountData)
    handler.cardDelivered(forAppID: identifier)
}
