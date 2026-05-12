public class JotformTotalCalculator {
    
    // 入力Wrapper（フローから受け取る）
    public class InputWrapper {
        @InvocableVariable(label='JotformオーダーID')
        public Id jotformOrderId;
    }
    
    // 結果Wrapper（フローに返す）
    public class ResultWrapper {
        @InvocableVariable
        public Boolean success;
        @InvocableVariable
        public String message;
        @InvocableVariable
        public Decimal mrrTotalPlus;
        @InvocableVariable
        public Decimal oneShotTotalPlus;
        @InvocableVariable
        public Decimal mrrTotalMinus;
        @InvocableVariable
        public Decimal oneShotTotalMinus;
        @InvocableVariable
        public Decimal discountTotalPlus;
        @InvocableVariable
        public Decimal discountTotalMinus;
    }
    
    /**
     * Jotformオーダーの合計を計算し、MRR_Total__c と OneShot_Total__c を更新
     * @param inputs 入力Wrapperのリスト（1件ずつ処理）
     * @return 結果Wrapperのリスト
     */
    @InvocableMethod(label='Jotformオーダーの合計を計算')
    public static List<ResultWrapper> calculateMonthlyTotals(List<InputWrapper> inputs) {
        
        List<ResultWrapper> results = new List<ResultWrapper>();
        
        try {
            // 入力チェック
            if (inputs == null || inputs.isEmpty()) {
                String execTime = Datetime.now().format('yyyy-MM-dd HH:mm:ss');
                ResultWrapper errorResult = new ResultWrapper();
                errorResult.success = false;
                errorResult.message = '（error）入力パラメータがありません。（実行日時：' + execTime + '）';
                results.add(errorResult);
                return results;
            }
            
            // ========== バルク処理用データ準備 ================================================================================
            
            // ① 全inputからJotformOrderIdを収集
            Set<Id> jotformOrderIds = new Set<Id>();
            for (InputWrapper input : inputs) {
                if (input.jotformOrderId != null) {
                    jotformOrderIds.add(input.jotformOrderId);
                }
            }
            
            // ② [商品とJotformの項目マッピング]オブジェクトのレコードを一括取得
            List<Product2_Jotform_Field_Map__c> mappings = [
                SELECT Product2__c, Jotform_Order_Target_Field__c, Discount_Product__c
                FROM Product2_Jotform_Field_Map__c
            ];
            
            // ※マッピングが0件の場合のエラーハンドリング
            if (mappings.isEmpty()) {
                for (InputWrapper input : inputs) {
                    String execTime = Datetime.now().format('yyyy-MM-dd HH:mm:ss');
                    ResultWrapper errorResult = new ResultWrapper();
                    errorResult.success = false;
                    errorResult.message = '（error）商品とJotformの項目マッピングが0件です。（実行日時：' + execTime + '）';
                    results.add(errorResult);
                }
                return results;
            }
            
            // ③ [Jotformオーダー]オブジェクトの動的クエリ用のフィールド名を準備
            Set<String> fieldNames = new Set<String>{'Id', 'Opportunity__c'};
            Set<Id> discountProductIds = new Set<Id>();
            for (Product2_Jotform_Field_Map__c mapping : mappings) {
                if (!String.isBlank(mapping.Jotform_Order_Target_Field__c)) {
                    fieldNames.add(mapping.Jotform_Order_Target_Field__c);
                }
                // ディスカウント商品IDを収集
                if (mapping.Discount_Product__c != null) {
                    discountProductIds.add(mapping.Discount_Product__c);
                }
            }
            
            // ④ [Jotformオーダー]オブジェクトの対象レコードを一括取得
            String fieldList = String.join(new List<String>(fieldNames), ',');
            String soql = 'SELECT ' + fieldList + ' FROM Jotform_Order__c WHERE Id IN :jotformOrderIds';
            Map<Id, Jotform_Order__c> jotformOrderMap = new Map<Id, Jotform_Order__c>();
            for (Jotform_Order__c order : Database.query(soql)) {
                jotformOrderMap.put(order.Id, order);
            }
            
            // ⑤ 取得した[JotformOrder]から商談IDを収集
            Set<Id> opportunityIds = new Set<Id>();
            for (Jotform_Order__c order : jotformOrderMap.values()) {
                if (order.Opportunity__c != null) {
                    opportunityIds.add(order.Opportunity__c);
                }
            }
            
            // ⑥ [商談]オブジェクトの対象レコードを一括取得
            Map<Id, Opportunity> opportunityMap = new Map<Id, Opportunity>([
                SELECT Id, Pricebook2Id FROM Opportunity WHERE Id IN :opportunityIds
            ]);
            
            // ⑦ マッピングから商品IDを収集
            Set<Id> productIds = new Set<Id>();
            for (Product2_Jotform_Field_Map__c mapping : mappings) {
                productIds.add(mapping.Product2__c);
            }
            
            // ⑧ [商品]オブジェクトの対象レコードを一括取得
            Map<Id, Boolean> productIsMRRMap = new Map<Id, Boolean>();
            for (Product2 p : [SELECT Id, is_MRR__c FROM Product2 WHERE Id IN :productIds]) {
                productIsMRRMap.put(p.Id, p.is_MRR__c);
            }
            
            // ⑨ 取得した[商談]から価格表IDを収集
            Set<Id> pricebookIds = new Set<Id>();
            for (Opportunity opp : opportunityMap.values()) {
                if (opp.Pricebook2Id != null) {
                    pricebookIds.add(opp.Pricebook2Id);
                }
            }
            
            // ⑩ [価格表エントリ]オブジェクトの対象レコードを一括取得
            Map<String, PricebookEntry> pbeMap = new Map<String, PricebookEntry>();
            for (PricebookEntry pbe : [
                SELECT Id, Product2Id, Pricebook2Id, UnitPrice
                FROM PricebookEntry
                WHERE Product2Id IN :productIds
                AND Pricebook2Id IN :pricebookIds
                AND IsActive = true
            ]) {
                pbeMap.put(pbe.Product2Id + '_' + pbe.Pricebook2Id, pbe);
            }
            
            // ⑪ [商談商品]オブジェクトの対象レコードを一括取得
            // 商品ごと、商談ごとにマップを作成（Key: OpportunityId + '_' + Product2Id）
            // ディスカウント商品についても OLI から単価を取得するため、全商品を取得
            Set<Id> allProductIds = new Set<Id>(productIds);
            allProductIds.addAll(discountProductIds);
            Map<String, OpportunityLineItem> oliMap = new Map<String, OpportunityLineItem>();
            for (OpportunityLineItem oli : [
                SELECT Id, OpportunityId, Product2Id, UnitPrice
                FROM OpportunityLineItem
                WHERE OpportunityId IN :opportunityIds
                AND Product2Id IN :allProductIds
                AND (Billing_end_date__c = null OR Billing_end_date__c >= :Date.today())
            ]) {
                oliMap.put(oli.OpportunityId + '_' + oli.Product2Id, oli);
            }
            
            // ========== 個別処理開始 ================================================================================
            
            List<Jotform_Order__c> ordersToUpdate = new List<Jotform_Order__c>();
            
            // 各inputを個別に処理
            for (InputWrapper input : inputs) {
                ResultWrapper result = new ResultWrapper();
                String execTime = Datetime.now().format('yyyy-MM-dd HH:mm:ss');
                
                try {
                    Id jotformOrderId = input.jotformOrderId;
                    
                    // Jotformオーダーの存在チェック
                    if (!jotformOrderMap.containsKey(jotformOrderId)) {
                        result.success = false;
                        result.message = '（error）対象のJotformオーダーがありません。（実行日時：' + execTime + '）';
                        results.add(result);
                        continue;
                    }
                    
                    Jotform_Order__c jotformOrder = jotformOrderMap.get(jotformOrderId);
                    
                    // 商談の存在チェック
                    if (jotformOrder.Opportunity__c == null || !opportunityMap.containsKey(jotformOrder.Opportunity__c)) {
                        result.success = false;
                        result.message = '（error）対象の商談がありません。Jotformオーダーの商談項目を確認してください。（実行日時：' + execTime + '）';
                        results.add(result);
                        continue;
                    }
                    
                    Opportunity opp = opportunityMap.get(jotformOrder.Opportunity__c);
                    
                    // 価格表チェック
                    if (opp.Pricebook2Id == null) {
                        result.success = false;
                        result.message = '（error）商談に価格表が設定されていません。商談の価格表を設定してください。（実行日時：' + execTime + '）';
                        results.add(result);
                        continue;
                    }
                    
                    // ========== 計算処理 ================================================================================
                    
                    Decimal mrrTotalPlus = 0;
                    Decimal oneShotTotalPlus = 0;
                    Decimal mrrTotalMinus = 0;
                    Decimal oneShotTotalMinus = 0;
                    Decimal discountTotalPlus = 0;
                    Decimal discountTotalMinus = 0;
                    
                    // マッピングループで各商品の金額を計算
                    for (Product2_Jotform_Field_Map__c mapping : mappings) {
                        
                        // Jotformオーダーの対象項目のAPI参照名を取得
                        String fieldApi = mapping.Jotform_Order_Target_Field__c;
                        if (String.isBlank(fieldApi)) continue;
                        
                        // 対象項目の値を取得
                        Object rawValue = jotformOrder.get(fieldApi);
                        if (rawValue == null) continue;
                        
                        // 数量に変換
                        Decimal quantity;
                        try {
                            quantity = (Decimal) rawValue;
                        } catch (Exception e) {
                            continue;
                        }
                        
                        // 0の場合はスキップ
                        if (quantity == 0) continue;
                        
                        // ========== 通常商品パス（既存ロジック・常に実行） ==========
                        
                        // 単価を取得（優先順序：商談商品 → 価格表エントリ）
                        Decimal unitPrice = null;
                        
                        // ① 商談商品から単価を取得
                        OpportunityLineItem oli = oliMap.get(opp.Id + '_' + mapping.Product2__c);
                        if (oli != null) {
                            unitPrice = oli.UnitPrice;
                        }
                        
                        // ② 商談商品がない場合は価格表から取得
                        if (unitPrice == null) {
                            PricebookEntry pbe = pbeMap.get(mapping.Product2__c + '_' + opp.Pricebook2Id);
                            if (pbe != null) {
                                unitPrice = pbe.UnitPrice;
                            }
                        }
                        
                        // 単価が取得できた場合、MRR/Shot合計に加算
                        if (unitPrice != null) {
                            Decimal amount = quantity * unitPrice;
                            
                            // MRR分類とプラス/マイナスで合計を加算
                            Boolean isMRR = productIsMRRMap.get(mapping.Product2__c);
                            if (amount > 0) {
                                if (isMRR) {
                                    mrrTotalPlus += amount;
                                } else {
                                    oneShotTotalPlus += amount;
                                }
                            } else if (amount < 0) {
                                if (isMRR) {
                                    mrrTotalMinus += amount;
                                } else {
                                    oneShotTotalMinus += amount;
                                }
                            }
                        }
                        
                        // ========== ディスカウント商品パス（通常パスとは独立して実行） ==========
                        if (mapping.Discount_Product__c != null) {
                            // ディスカウント商品の OLI から単価を取得（必須・PricebookEntry は参照しない）
                            OpportunityLineItem discountOli = oliMap.get(opp.Id + '_' + mapping.Discount_Product__c);
                            if (discountOli != null && discountOli.UnitPrice != null) {
                                // 金額計算
                                Decimal discountAmount = quantity * discountOli.UnitPrice;
                                
                                // ディスカウント合計に加算
                                if (discountAmount > 0) {
                                    discountTotalPlus += discountAmount;
                                } else if (discountAmount < 0) {
                                    discountTotalMinus += discountAmount;
                                }
                            }
                        }
                    }
                    
                    // ========== Jotform_Order__c を更新用にセット ================================================================================
                    
                    Jotform_Order__c orderToUpdate = new Jotform_Order__c();
                    orderToUpdate.Id = jotformOrderId;
                    orderToUpdate.put('MRR_Total_Plus__c', mrrTotalPlus);
                    orderToUpdate.put('OneShot_Total_Plus__c', oneShotTotalPlus);
                    orderToUpdate.put('MRR_Total_Minus__c', mrrTotalMinus);
                    orderToUpdate.put('OneShot_Total_Minus__c', oneShotTotalMinus);
                    orderToUpdate.put('Discount_Total_Plus__c', discountTotalPlus);
                    orderToUpdate.put('Discount_Total_Minus__c', discountTotalMinus);
                    ordersToUpdate.add(orderToUpdate);
                    
                    // 成功結果を返却
                    result.success = true;
                    result.message = '（success）合計の計算処理を実行しました。（実行日時：' + execTime + '）';
                    result.mrrTotalPlus = mrrTotalPlus;
                    result.oneShotTotalPlus = oneShotTotalPlus;
                    result.mrrTotalMinus = mrrTotalMinus;
                    result.oneShotTotalMinus = oneShotTotalMinus;
                    result.discountTotalPlus = discountTotalPlus;
                    result.discountTotalMinus = discountTotalMinus;
                    
                } catch (Exception ex) {
                    result.success = false;
                    result.message = '（error）エラーが発生しました: ' + ex.getMessage() + '（実行日時：' + execTime + '）';
                }
                
                results.add(result);
            }
            
            // ========== 一括更新実行 ========================================
            
            if (!ordersToUpdate.isEmpty()) {
                update ordersToUpdate;
            }
            
        } catch (Exception ex) {
            // 全体的なエラーの場合、各inputに対してエラーを返す
            String execTime = Datetime.now().format('yyyy-MM-dd HH:mm:ss');
            for (Integer i = results.size(); i < inputs.size(); i++) {
                ResultWrapper errorResult = new ResultWrapper();
                errorResult.success = false;
                errorResult.message = '（error）システムエラーが発生しました: ' + ex.getMessage() + '（実行日時：' + execTime + '）';
                results.add(errorResult);
            }
        }
        
        return results;
    }
}