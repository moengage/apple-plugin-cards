// Type 2 — Completion handler (dominant pattern in apple-plugin-cards)
// Use when: nativeToHybrid contract exists AND native API has a completion closure.
// The bridge method itself takes a completionHandler param — hybrid caller gets result directly.
// Response is built via MoEngagePluginCardsUtil.buildHybridPayload.
// Example: fetchCards, getCardsInfo, getNewCardsCount, isAllCategoryEnabled

@objc public func <methodName>(
    _ payload: [String: Any],
    completionHandler: @escaping ([String: Any]) -> Void
) {
    guard
        let identifier = MoEngagePluginUtils.fetchIdentifierFromPayload(attribute: payload)
    else {
        logAppIdentifierFetchFailed(for: payload)
        return
    }
    MoEngagePluginCardsLogger.debug("<MethodName> - ", forData: payload)
    handler.<nativeMethod>(forAppID: identifier) { nativeResult in
        let result = MoEngagePluginCardsUtil.buildHybridPayload(
            forIdentifier: identifier,
            containingData: [
                MoEngagePluginCardsContants.<responseKey>: nativeResult?.<responseField> as Any
            ]
        )
        MoEngagePluginCardsLogger.debug("<MethodName> response - ", forData: result)
        completionHandler(result)
    }
}

// Real example — getNewCardsCount
@objc public func getNewCardsCount(
    _ accountData: [String: Any],
    completionHandler: @escaping ([String: Any]) -> Void
) {
    guard
        let identifier = MoEngagePluginUtils.fetchIdentifierFromPayload(attribute: accountData)
    else {
        logAppIdentifierFetchFailed(for: accountData)
        return
    }
    MoEngagePluginCardsLogger.debug("Fetch New Cards Count - ", forData: accountData)
    handler.getNewCardsCount(forAppID: identifier) { count, accountMeta in
        let result = MoEngagePluginCardsUtil.buildHybridPayload(
            forIdentifier: identifier,
            containingData: [
                MoEngagePluginCardsContants.newCardsCount: count
            ]
        )
        MoEngagePluginCardsLogger.debug("Fetch New Cards Count response - ", forData: result)
        completionHandler(result)
    }
}

// Real example — fetchCards (response is a HybridEncodable model)
@objc public func fetchCards(
    _ accountData: [String: Any],
    completionHandler: @escaping ([String: Any]) -> Void
) {
    guard
        let identifier = MoEngagePluginUtils.fetchIdentifierFromPayload(attribute: accountData)
    else {
        logAppIdentifierFetchFailed(for: accountData)
        return
    }
    MoEngagePluginCardsLogger.debug("Fetch Cards - ", forData: accountData)
    handler.fetchCards(forAppID: identifier) { data in
        let result = MoEngagePluginCardsUtil.buildHybridPayload(
            forIdentifier: identifier,
            containingData: data?.encodeForHybrid() ?? [:]
        )
        MoEngagePluginCardsLogger.debug("Fetch Cards response - ", forData: result)
        completionHandler(result)
    }
}

// Real example — input requires decoding from hybrid payload before calling native
@objc public func cardShown(_ cardData: [String: Any]) {
    guard
        let identifier = MoEngagePluginUtils.fetchIdentifierFromPayload(attribute: cardData)
    else {
        logAppIdentifierFetchFailed(for: cardData)
        return
    }
    MoEngagePluginCardsLogger.debug("Cards Shown ", forData: cardData)
    do {
        let showData: [String: Any] = try MoEngagePluginCardsUtil.getNestedData(
            fromHybridPayload: cardData,
            forKey: MoEngagePluginCardsContants.card
        )
        let card = try MoEngageHybridSDKCards.buildCardCampaign(fromHybridData: showData)
        handler.cardShown(card, forAppID: identifier)
    } catch {
        MoEngagePluginCardsLogger.error("\(error)")
    }
}
