public without sharing class RollupCurrencyInfo {
  public static final String CURRENCY_ISO_CODE_FIELD_NAME = 'CurrencyIsoCode';

  @TestVisible
  private static Map<String, RollupCurrencyInfo> mockCurrencyData;
  private static final Map<Id, SObject> TRANSFORMED_MULTICURRENCY_CALC_ITEMS = new Map<Id, SObject>();
  private static final Set<String> HASHED_ITEM_VALUES = new Set<String>();

  @TestVisible
  private static Boolean IS_MULTICURRENCY {
    get {
      if (IS_MULTICURRENCY == null) {
        IS_MULTICURRENCY = UserInfo.isMultiCurrencyOrganization();
      }
      return IS_MULTICURRENCY;
    }
    set;
  }

  private static final RollupCurrencyInfo FALLBACK_INFO {
    get {
      if (FALLBACK_INFO == null) {
        FALLBACK_INFO = new RollupCurrencyInfo();
        FALLBACK_INFO.DecimalPlaces = 2;
        FALLBACK_INFO.ConversionRate = 1;
      }
      return FALLBACK_INFO;
    }
    set;
  }

  private static final Map<String, RollupCurrencyInfo> CURRENCY_ISO_CODE_TO_CURRENCY {
    get {
      if (CURRENCY_ISO_CODE_TO_CURRENCY == null) {
        CURRENCY_ISO_CODE_TO_CURRENCY = getCurrencyMap();
      }
      return CURRENCY_ISO_CODE_TO_CURRENCY;
    }
    set;
  }

  public String IsoCode { get; set; }
  public Decimal ConversionRate { get; set; }
  public Integer DecimalPlaces { get; set; }
  public Boolean IsCorporate { get; set; }

  public static Boolean isMultiCurrency() {
    return IS_MULTICURRENCY;
  }

  public static SObject getCalcItem(SObject calcItem) {
    return TRANSFORMED_MULTICURRENCY_CALC_ITEMS.containsKey(calcItem.Id) ? TRANSFORMED_MULTICURRENCY_CALC_ITEMS.get(calcItem.Id) : calcItem;
  }

  public static RollupCurrencyInfo getCurrencyInfo(String currencyIsoCode) {
    return CURRENCY_ISO_CODE_TO_CURRENCY.containsKey(currencyIsoCode) ? CURRENCY_ISO_CODE_TO_CURRENCY.get(currencyIsoCode) : FALLBACK_INFO;
  }

  public static void setCurrencyIsoCode(SObject record, String isoCode) {
    if (IS_MULTICURRENCY) {
      record.put(CURRENCY_ISO_CODE_FIELD_NAME, isoCode);
    }
  }

  public static SObject createNewRecord(SObject originalParent) {
    SObject newParent = originalParent.getSObjectType().newSObject(originalParent.Id);
    if (isMultiCurrency()) {
      newParent.put(CURRENCY_ISO_CODE_FIELD_NAME, originalParent.get(CURRENCY_ISO_CODE_FIELD_NAME));
    }
    return newParent;
  }

  public static void transformForMultiCurrencyOrgs(
    SObject calcItem,
    Schema.SObjectField opFieldOnCalcItem,
    String parentIsoCode,
    List<RollupOrderBy__mdt> orderBys
  ) {
    if (calcItem.getSObjectType().getDescribe().fields.getMap().containsKey(CURRENCY_ISO_CODE_FIELD_NAME)) {
      String calcItemIsoCode = (String) calcItem.get(CURRENCY_ISO_CODE_FIELD_NAME);
      SObject clonedCalcItem = TRANSFORMED_MULTICURRENCY_CALC_ITEMS.get(calcItem.Id);
      String hashKey = getHashKey(calcItem, opFieldOnCalcItem);
      if (
        String.isBlank(parentIsoCode) ||
        String.isBlank(calcItemIsoCode) ||
        calcItemIsoCode == parentIsoCode ||
        HASHED_ITEM_VALUES.contains(hashKey) ||
        CURRENCY_ISO_CODE_TO_CURRENCY.containsKey(calcItemIsoCode) == false ||
        CURRENCY_ISO_CODE_TO_CURRENCY.containsKey(parentIsoCode) == false ||
        calcItem.get(opFieldOnCalcItem) == 0
      ) {
        return;
      }
      // the worst possible scenario has occurred - the currencies differ and we haven't already populated the map
      clonedCalcItem = clonedCalcItem == null ? calcItem.clone(true, true, true, true) : clonedCalcItem;
      convertToParentCurrency(calcItem, clonedCalcItem, opFieldOnCalcItem, calcItemIsoCode, parentIsoCode, hashKey);

      for (RollupOrderBy__mdt orderBy : orderBys) {
        Schema.SObjectField orderByFirstLastField = calcItem.getSObjectType().getDescribe().fields.getMap().get(orderBy.FieldName__c);
        if (orderByFirstLastField != null && orderByFirstLastField != opFieldOnCalcItem) {
          String orderByHashKey = getHashKey(calcItem, orderByFirstLastField);
          convertToParentCurrency(calcItem, clonedCalcItem, orderByFirstLastField, calcItemIsoCode, parentIsoCode, orderByHashKey);
        }
      }

      TRANSFORMED_MULTICURRENCY_CALC_ITEMS.put(calcItem.Id, clonedCalcItem);
    }
  }

  private static void convertToParentCurrency(
    SObject calcItem,
    SObject clonedCalcItem,
    SObjectField fieldOnCalcItem,
    String calcItemIsoCode,
    String parentIsoCode,
    String hashKey
  ) {
    if (fieldOnCalcItem.getDescribe().getType() != DisplayType.CURRENCY) {
      return;
    }

    Decimal calcItemDenominator = (Decimal) calcItem.get(fieldOnCalcItem);
    if (calcItemDenominator != null) {
      Decimal calcItemAmountInOrgCurrency = CURRENCY_ISO_CODE_TO_CURRENCY.get(calcItemIsoCode).ConversionRate / calcItemDenominator;
      Decimal calcItemAmountInParentCurrency = CURRENCY_ISO_CODE_TO_CURRENCY.get(parentIsoCode).ConversionRate / calcItemAmountInOrgCurrency;
      clonedCalcItem.put(CURRENCY_ISO_CODE_FIELD_NAME, parentIsoCode);
      clonedCalcItem.put(fieldOnCalcItem, calcItemAmountInParentCurrency);
      HASHED_ITEM_VALUES.add(hashKey);
    }
  }

  private static String getHashKey(SObject calcItem, Schema.SObjectField opFieldOnCalcItem) {
    return '' + calcItem.Id + opFieldOnCalcItem.getDescribe().getName();
  }

  private static Map<String, RollupCurrencyInfo> getCurrencyMap() {
    if (mockCurrencyData != null) {
      return mockCurrencyData;
    }

    Map<String, RollupCurrencyInfo> currencyInfoMap = new Map<String, RollupCurrencyInfo>();
    if (IS_MULTICURRENCY == false) {
      return currencyInfoMap;
    }

    String query = 'SELECT IsoCode, ConversionRate, DecimalPlaces, IsCorporate FROM CurrencyType WHERE IsActive = TRUE';
    List<RollupCurrencyInfo> currencyTypes = (List<RollupCurrencyInfo>) JSON.deserialize(JSON.serialize(Database.query(query)), List<RollupCurrencyInfo>.class);
    for (RollupCurrencyInfo currencyType : currencyTypes) {
      currencyInfoMap.put(currencyType.IsoCode, currencyType);
    }
    return currencyInfoMap;
  }
}
