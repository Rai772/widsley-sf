public class JotformOppProductUpdate {
    
    // フローから渡される入力クラス
    public class InputWrapper {
        @InvocableVariable(label='JotformオーダーID')
        public Id jotformOrderId;
        @InvocableVariable(label='処理モード（add/reduce）') // 'add' or 'reduce'
        public String mode;
    }
    
    // フローに返す結果クラス
    public class ResultWrapper {
        @InvocableVariable public Boolean success; // 成功かどうか
        @InvocableVariable public String message;  // 結果メッセージ
    }
    
    
    
    // フローから呼び出すメインメソッド（バルク処理対応）
    @InvocableMethod(label='Jotformオーダーを基に商談商品を更新')
    public static List<ResultWrapper> updateOppProducts(List<InputWrapper> inputs) {
        
        List<ResultWrapper> results = new List<ResultWrapper>();
        
        try {
            // 入力チェック（IDがなければエラー）
            if (inputs == null || inputs.isEmpty()) {
                String execTime = Datetime.now().format('yyyy-MM-dd HH:mm:ss');
                ResultWrapper errorResult = new ResultWrapper();
                errorResult.success = false;
                errorResult.message = '（error）入力パラメータがありません。（実行日時：' + execTime + '）';
                results.add(errorResult);
                return results;
            }
            
            // ========== バルク処理用データ準備 ================================================================================
            
            // ① 全inputからJotformOrderIdとmodeを収集
            Set<Id> jotformOrderIds = new Set<Id>();
            
            // ※収集ループ
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
            
            // ※[商品とJotformの項目マッピング]のレコードが0件の場合のエラーハンドリング
            if (mappings.isEmpty()) {
                // 全inputに対してエラーを返す
                for (InputWrapper input : inputs) {
                    String execTime = Datetime.now().format('yyyy-MM-dd HH:mm:ss');
                    ResultWrapper errorResult = new ResultWrapper();
                    errorResult.success = false;
                    errorResult.message = '（error）商品とJotformの項目マッピングが0件です。（実行日時：' + execTime + '）';
                    results.add(errorResult);
                }
                return results;
            }
            
            // ※[Jotformオーダー]オブジェクトの動的クエリ用のフィールド名の準備
            Set<String> fieldNames = new Set<String>{'Id', 'Account_Code__c', 'Form_Registration_DateTime__c', 'Opportunity_Product_Up_Date__c', 'Opportunity_Product_Down_Date__c', 'Opportunity__c'};
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
            
            // ③[Jotformオーダー]オブジェクトの対象レコードを一括取得
            String fieldList = String.join(new List<String>(fieldNames), ',');
            String soql = 'SELECT ' + fieldList + ' FROM Jotform_Order__c WHERE Id IN :jotformOrderIds';
            Map<Id, Jotform_Order__c> jotformOrderMap = new Map<Id, Jotform_Order__c>();
            for (Jotform_Order__c order : Database.query(soql)) {
                jotformOrderMap.put(order.Id, order);
            }
            
            // ※取得した[JotformOrder]から商談IDを収集し、Setに追加
            Set<Id> opportunityIds = new Set<Id>();
            for (Jotform_Order__c order : jotformOrderMap.values()) {
                if (order.Opportunity__c != null) {
                    opportunityIds.add(order.Opportunity__c);
                }
            }
            
            // ④[商談]オブジェクトの対象レコードを一括取得（FOR UPDATEでロック）
            // 並行実行による重複作成を防ぐため、商談レコードをロック
            Map<Id, Opportunity> opportunityMap = new Map<Id, Opportunity>([
                SELECT Id, Pricebook2Id FROM Opportunity WHERE Id IN :opportunityIds FOR UPDATE
            ]);
            
            // ※取得した[商品とJotformの項目マッピング]から商品IDを収集し、Setに追加
            Set<Id> productIds = new Set<Id>();
            for (Product2_Jotform_Field_Map__c mapping : mappings) {
                productIds.add(mapping.Product2__c);
            }
            
            // ⑤[商品]オブジェクトの対象レコードを一括取得
            Map<Id, Boolean> productIsMRRMap = new Map<Id, Boolean>();
            for (Product2 p : [SELECT Id, is_MRR__c FROM Product2 WHERE Id IN :productIds]) {
                productIsMRRMap.put(p.Id, p.is_MRR__c);
            }
            
            // ※ 取得した[商談]から価格表IDを収集し、Setに追加
            Set<Id> pricebookIds = new Set<Id>();
            for (Opportunity opp : opportunityMap.values()) {
                if (opp.Pricebook2Id != null) {
                    pricebookIds.add(opp.Pricebook2Id);
                }
            }
            
            // ⑥[価格表エントリ]オブジェクトの対象レコードを一括取得
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
            
            // ⑦取得した[商談商品]オブジェクトの対象レコードを一括取得
            // UnitPriceも取得して現在の価格を保持し、自動更新を防ぐ
            // 請求終了している商品は除外（Billing_end_date__c = null のみを対象）
            // ディスカウント商品についても OLI から単価を取得するため、全商品（通常+ディスカウント）を取得
            Set<Id> allProductIds = new Set<Id>(productIds);
            allProductIds.addAll(discountProductIds);
            Map<Id, Map<Id, OpportunityLineItem>> existingItemsMap = new Map<Id, Map<Id, OpportunityLineItem>>();
            for (OpportunityLineItem oli : [
                SELECT Id, OpportunityId, Product2Id, Quantity, UnitPrice, Billing_end_date__c
                FROM OpportunityLineItem 
                WHERE OpportunityId IN :opportunityIds
                AND (Billing_end_date__c = null OR Billing_end_date__c >= :Date.today())
                AND Product2Id IN :allProductIds
            ]) {
                if (!existingItemsMap.containsKey(oli.OpportunityId)) {
                    existingItemsMap.put(oli.OpportunityId, new Map<Id, OpportunityLineItem>());
                }
                existingItemsMap.get(oli.OpportunityId).put(oli.Product2Id, oli);
            }
            
            // ========== 個別処理開始 ================================================================================
            
            // DML用のコレクション
            List<OpportunityLineItem> allToInsert = new List<OpportunityLineItem>();
            List<OpportunityLineItem> allToUpdate = new List<OpportunityLineItem>();
            
            /*
            ここから[Jotformオーダー]を1件ずつの処理
                ループ内でDMLは行わず、DML用リストに追加していく
                 */
            
            // 各inputを個別に処理
            for (InputWrapper input : inputs) {
                ResultWrapper result = new ResultWrapper(); // 結果用クラス
                String execTime = Datetime.now().format('yyyy-MM-dd HH:mm:ss');
                
                try {
                    
                    // 個別処理
                    Id jotformOrderId = input.jotformOrderId;
                    String mode = input.mode;
                    
                    // JotformOrderの存在チェック
                    if (!jotformOrderMap.containsKey(jotformOrderId)) {
                        result.success = false;
                        result.message = '（error）対象のJotformオーダーがありません。（実行日時：' + execTime + '）';
                        results.add(result);
                        continue;
                    }
                    
                    // JotformOrderの格納
                    Jotform_Order__c jotformOrder = jotformOrderMap.get(jotformOrderId);
                    
                    // 商談の存在チェック
                    if (!opportunityMap.containsKey(jotformOrder.Opportunity__c)) {
                        result.success = false;
                        result.message = '（error）対象の商談がありません。Jotformオーダーの商談項目を確認してください。（実行日時：' + execTime + '）';
                        results.add(result);
                        continue;
                    }
                    
                    // 商談の格納
                    Opportunity opp = opportunityMap.get(jotformOrder.Opportunity__c);
                    
                    // 価格表チェック
                    if (opp.Pricebook2Id == null) {
                        result.success = false;
                        result.message = '（error）商談に価格表が設定されていません。商談の価格表を設定してください。（実行日時：' + execTime + '）';
                        results.add(result);
                        continue;
                    }
                    
                    // 既存商談商品の取得
                    Map<Id, OpportunityLineItem> currentExistingItems = existingItemsMap.get(opp.Id);
                    if (currentExistingItems == null) {
                        currentExistingItems = new Map<Id, OpportunityLineItem>();
                    }
                    
                    // この入力での処理用リスト
                    List<OpportunityLineItem> toInsert = new List<OpportunityLineItem>();
                    List<OpportunityLineItem> toUpdate = new List<OpportunityLineItem>();
                    
                    // [商品とJotformの項目マッピング]ループ処理
                    for (Product2_Jotform_Field_Map__c mapping : mappings) {
                        
                        /*
                        処理前の準備
                             */
                        
                        // [Jotformオーダーの対象項目のAPI参照名]の値を取得
                        String fieldApi = mapping.Jotform_Order_Target_Field__c;
                        if (String.isBlank(fieldApi)) continue; // 空の場合はこのループをスキップ
                        
                        // [Jotformオーダー]の対象項目の値を取得
                        Object rawValue = jotformOrder.get(fieldApi);
                        if (rawValue == null) continue; // 空の場合はこのループをスキップ
                        
                        // 『数量』の定義と型変換
                        Decimal quantity;
                        try {
                            quantity = (Decimal) rawValue; // 対象項目の値をDecimal型に変換
                        } catch (Exception e) {
                            continue; // 型変換できなければこのループをスキップ
                        }
                        
                        /*
                        メインの処理
                             */
                        
                        // 追加モード処理
                        if (mode == 'add') {
                            // 1未満は追加対象外（0やマイナスは無視）
                            if (quantity < 1) continue;
                            
                            // 既存[商談商品]があれば数量を加算して更新
                            if (currentExistingItems.containsKey(mapping.Product2__c)) {
                                
                                //======
                                //加算_更新
                                //======
                                
                                OpportunityLineItem existing = currentExistingItems.get(mapping.Product2__c);
                                
                                // toUpdate内に同じ商談商品が既に更新候補として存在するかチェック
                                OpportunityLineItem foundInUpdate = null;
                                for (OpportunityLineItem item : toUpdate) {
                                    if (item.Id == existing.Id) {
                                        foundInUpdate = item;
                                        break;
                                    }
                                }
                                
                                // allToUpdate内に同じ商談商品が既に更新候補として存在するかチェック
                                OpportunityLineItem globalFoundInUpdate = null;
                                for (OpportunityLineItem item : allToUpdate) {
                                    if (item.Id == existing.Id) {
                                        globalFoundInUpdate = item;
                                        break;
                                    }
                                }
                                
                                if (foundInUpdate != null) {
                                    // toUpdate内に既に存在する場合は数量のみ加算
                                    foundInUpdate.Quantity += quantity;
                                } else if (globalFoundInUpdate != null) {
                                    // allToUpdate内に既に存在する場合は数量のみ加算
                                    globalFoundInUpdate.Quantity += quantity;
                                } else {
                                    // どちらにも存在しない場合は数量加算してtoUpdateに追加
                                    existing.Quantity += quantity;
                                    // UnitPriceを明示的に設定して価格変更を防ぐ
                                    existing.UnitPrice = existing.UnitPrice;
                                    toUpdate.add(existing);
                                }
                            } else {
                                
                                //======
                                //加算_新規作成
                                //======
                                
                                // toInsert内に同じ商談商品が既に新規作成候補として存在するかチェック
                                OpportunityLineItem found = null;
                                for (OpportunityLineItem item : toInsert) {
                                    if (item.Product2Id == mapping.Product2__c) {
                                        found = item;
                                        break;
                                    }
                                }
                                
                                // allToInsert内に同じ商談商品の組み合わせが既に存在するかチェック
                                OpportunityLineItem globalFound = null;
                                for (OpportunityLineItem item : allToInsert) {
                                    if (item.Product2Id == mapping.Product2__c && item.OpportunityId == opp.Id) {
                                        globalFound = item;
                                        break;
                                    }
                                }
                                
                                if (found != null) {
                                    // toInsert内に新規作成候補があれば数量加算
                                    found.Quantity += quantity;
                                } else if (globalFound != null) {
                                    // allToInsert内に既存の新規作成候補があれば数量加算
                                    globalFound.Quantity += quantity;
                                } else {
                                    // 既存商品も新規作成候補もなければ新規作成
                                    PricebookEntry pbe = pbeMap.get(mapping.Product2__c + '_' + opp.Pricebook2Id);
                                    if (pbe == null) {
                                        // 価格表に商品がなければエラー
                                        result.success = false;
                                        result.message = '（error）商品ID: ' + mapping.Product2__c + ' が商談の価格表に登録されていません。価格表に商品を追加するか、商談の価格表を確認してください。（実行日時：' + execTime + '）';
                                        results.add(result);
                                        continue;
                                    }
                                    
                                    // 新規 OpportunityLineItem の作成
                                    OpportunityLineItem newItem = new OpportunityLineItem();
                                    newItem.OpportunityId = opp.Id; // 商談ID
                                    newItem.PricebookEntryId = pbe.Id; // 価格表エントリID
                                    newItem.Product2Id = mapping.Product2__c; // 商品ID
                                    newItem.Quantity = quantity; // 追加数量
                                    newItem.UnitPrice = pbe.UnitPrice; // 単価
                                    
                                    // 登録日があればセット
                                    if (jotformOrder.Form_Registration_DateTime__c != null) {
                                        newItem.OrderDate__c = jotformOrder.Form_Registration_DateTime__c.date();
                                    }
                                    // 利用開始日・請求開始日をセット
                                    newItem.start_date_of_use__c = jotformOrder.Opportunity_Product_Up_Date__c;
                                    newItem.Billing_start_date__c = jotformOrder.Opportunity_Product_Up_Date__c;
                                    
                                    // MRR商品以外は月末で請求終了日をセット
                                    Boolean isMRR = productIsMRRMap.get(mapping.Product2__c);
                                    if (!isMRR && jotformOrder.Opportunity_Product_Up_Date__c != null) {
                                        Date billingStart = jotformOrder.Opportunity_Product_Up_Date__c;
                                        Date endOfMonth = Date.newInstance(billingStart.year(), billingStart.month(), 1).addMonths(1).addDays(-1);
                                        newItem.Billing_end_date__c = endOfMonth;
                                    }
                                    toInsert.add(newItem); // 挿入リストに追加
                                }
                            }
                        }
                        // 削減モード
                        else if (mode == 'reduce') {
                            
                            //======
                            //削減_更新
                            //======
                            
                            if (quantity > -1) continue;
                            if (currentExistingItems.containsKey(mapping.Product2__c)) {
                                OpportunityLineItem existing = currentExistingItems.get(mapping.Product2__c);
                                Date reductionDate = jotformOrder.Opportunity_Product_Down_Date__c;
                                
                                // toUpdate内に同じ商談商品が既に更新候補として存在するかチェック
                                OpportunityLineItem foundInUpdate = null;
                                for (OpportunityLineItem item : toUpdate) {
                                    if (item.Id == existing.Id) {
                                        foundInUpdate = item;
                                        break;
                                    }
                                }
                                
                                // allToUpdate内に同じ商談商品が既に更新候補として存在するかチェック
                                OpportunityLineItem globalFoundInUpdate = null;
                                for (OpportunityLineItem item : allToUpdate) {
                                    if (item.Id == existing.Id) {
                                        globalFoundInUpdate = item;
                                        break;
                                    }
                                }
                                
                                if (foundInUpdate != null) {
                                    // toUpdate内に既に存在する場合
                                    foundInUpdate.Quantity += quantity;
                                    setBillingEndDateIfZero(foundInUpdate, reductionDate);
                                } else if (globalFoundInUpdate != null) {
                                    // allToUpdate内に既に存在する場合
                                    globalFoundInUpdate.Quantity += quantity;
                                    setBillingEndDateIfZero(globalFoundInUpdate, reductionDate);
                                } else {
                                    // どちらにも存在しない場合は新規更新
                                    existing.Quantity += quantity;
                                    setBillingEndDateIfZero(existing, reductionDate);
                                    // UnitPriceを明示的に設定して価格変更を防ぐ
                                    existing.UnitPrice = existing.UnitPrice;
                                    toUpdate.add(existing);
                                }
                            }
                        }
                        
                        // ========== ディスカウント商品処理（通常商品処理後に実行） ==========
                        // 設計要件：ディスカウント商品の数量 = 通常商品の加算後/削減後の最終数量（上書き）
                        if (mapping.Discount_Product__c != null) {
                            if (mode == 'add' && quantity >= 1) {
                                // 加算モード：通常商品が存在する場合のみ処理
                                if (currentExistingItems.containsKey(mapping.Product2__c)) {
                                    OpportunityLineItem normalOli = currentExistingItems.get(mapping.Product2__c);
                                    OpportunityLineItem discountOli = currentExistingItems.get(mapping.Discount_Product__c);
                                    
                                    if (discountOli != null) {
                                        // ディスカウント商品の OLI が存在する場合、通常商品の最終数量で上書き
                                        // ※通常商品の加算処理が既に完了し、normalOli.Quantity に最終数量が反映されている
                                        Decimal normalProductFinalQuantity = normalOli.Quantity;
                                        
                                        OpportunityLineItem foundInUpdate = null;
                                        for (OpportunityLineItem item : toUpdate) {
                                            if (item.Id == discountOli.Id) {
                                                foundInUpdate = item;
                                                break;
                                            }
                                        }
                                        
                                        OpportunityLineItem globalFoundInUpdate = null;
                                        for (OpportunityLineItem item : allToUpdate) {
                                            if (item.Id == discountOli.Id) {
                                                globalFoundInUpdate = item;
                                                break;
                                            }
                                        }
                                        
                                        if (foundInUpdate != null) {
                                            // toUpdate内のディスカウントOLIが既に存在する場合
                                            foundInUpdate.Quantity = normalProductFinalQuantity;
                                        } else if (globalFoundInUpdate != null) {
                                            // allToUpdate内のディスカウントOLIが既に存在する場合
                                            globalFoundInUpdate.Quantity = normalProductFinalQuantity;
                                        } else {
                                            // 新規でtoUpdateに追加
                                            discountOli.Quantity = normalProductFinalQuantity;
                                            // ★以下はSalesforce の自動計算機能で UnitPrice が自動更新されるのを防止
                                            // 明示的に元の値を代入して固定
                                            discountOli.UnitPrice = discountOli.UnitPrice;
                                            toUpdate.add(discountOli);
                                        }
                                    }
                                }
                            } else if (mode == 'reduce' && quantity <= -1) {
                                // 削減モード：通常商品が存在する場合のみ処理
                                if (currentExistingItems.containsKey(mapping.Product2__c)) {
                                    OpportunityLineItem normalOli = currentExistingItems.get(mapping.Product2__c);
                                    OpportunityLineItem discountOli = currentExistingItems.get(mapping.Discount_Product__c);
                                    Date reductionDate = jotformOrder.Opportunity_Product_Down_Date__c;
                                    
                                    if (discountOli != null) {
                                        // ディスカウント商品の OLI が存在する場合、通常商品の最終数量で上書き
                                        // ※通常商品の削減処理が既に完了し、normalOli.Quantity に最終数量が反映されている
                                        Decimal normalProductFinalQuantity = normalOli.Quantity;
                                        
                                        OpportunityLineItem foundInUpdate = null;
                                        for (OpportunityLineItem item : toUpdate) {
                                            if (item.Id == discountOli.Id) {
                                                foundInUpdate = item;
                                                break;
                                            }
                                        }
                                        
                                        OpportunityLineItem globalFoundInUpdate = null;
                                        for (OpportunityLineItem item : allToUpdate) {
                                            if (item.Id == discountOli.Id) {
                                                globalFoundInUpdate = item;
                                                break;
                                            }
                                        }
                                        
                                        if (foundInUpdate != null) {
                                            // toUpdate内のディスカウントOLIが既に存在する場合
                                            foundInUpdate.Quantity = normalProductFinalQuantity;
                                            setBillingEndDateIfZero(foundInUpdate, reductionDate);
                                        } else if (globalFoundInUpdate != null) {
                                            // allToUpdate内のディスカウントOLIが既に存在する場合
                                            globalFoundInUpdate.Quantity = normalProductFinalQuantity;
                                            setBillingEndDateIfZero(globalFoundInUpdate, reductionDate);
                                        } else {
                                            // 新規でtoUpdateに追加
                                            discountOli.Quantity = normalProductFinalQuantity;
                                            setBillingEndDateIfZero(discountOli, reductionDate);
                                            // ★以下はSalesforce の自動計算機能で UnitPrice が自動更新されるのを防止
                                            // 明示的に元の値を代入して固定
                                            discountOli.UnitPrice = discountOli.UnitPrice;
                                            toUpdate.add(discountOli);
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // 全体のDMLリストに追加
                    allToInsert.addAll(toInsert);
                    
                    // allToUpdateへの追加
                    // 重複更新を防ぐため、既にallToUpdateに含まれていない商品のみ追加
                    for (OpportunityLineItem updateItem : toUpdate) {
                        Boolean alreadyExists = false;
                        for (OpportunityLineItem existingUpdateItem : allToUpdate) {
                            if (existingUpdateItem.Id == updateItem.Id) {
                                alreadyExists = true;
                                break;
                            }
                        }
                        if (!alreadyExists) {
                            // 全体のDMLリストに追加
                            allToUpdate.add(updateItem);
                        }
                    }
                    
                    // 成功結果を追加
                    result.success = true;
                    if (mode == 'add') {
                        result.message = '（success）商談商品の数量の追加処理を実行しました。（実行日時：' + execTime + '）';
                    } else if (mode == 'reduce') {
                        result.message = '（success）商談商品の数量の削減処理を実行しました。（実行日時：' + execTime + '）';
                    }
                    
                } catch (Exception ex) {
                    result.success = false;
                    result.message = '（error）エラーが発生しました: ' + ex.getMessage() + '（実行日時：' + execTime + '）';
                }
                
                results.add(result);
            }
            
            // ========== バルクDML実行 ========================================
            
            if (!allToInsert.isEmpty()) {
                insert allToInsert;
            }
            
            if (!allToUpdate.isEmpty()) {
                update allToUpdate;
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
    
    // 削減処理で請求終了日設定を行うヘルパーメソッド
    private static void setBillingEndDateIfZero(OpportunityLineItem item, Date reductionDate) {
        // 数量が0以下になった場合は請求終了日を設定
        if (item.Quantity <= 0) {
            if (reductionDate != null) {
                item.Billing_end_date__c = reductionDate.addDays(-1);
            }
        }
    }
}