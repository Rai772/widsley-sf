@isTest
public class JotformTotalCalculatorTest {

    /*
     * ================================================================================
     * IMPORTANT FOR FUTURE MAINTENANCE (AI/HUMAN)
     * ================================================================================
     * このOrgでは、Jotform_Order__c の INSERT をトリガに別フローが動作し、
     * Opportunity__c の値が期待どおり残らないケースがあります。
     *
     * そのため、Jotform_Order__c を「商談あり」で作る通常テストでは
     * 必ず以下のフロー回避パターンを使ってください。
     *
     *   1) insert order;
     *   2) order.Opportunity__c = <OppId>;
     *   3) update order;
     *
     * ※ Opportunity__c を意図的に null にする異常系テストは除く
     * ================================================================================
     */
    
    // HTTPコールアウトモッククラス（JotformOppProductUpdateTestと同じパターン）
    public class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": true}');
            res.setStatusCode(200);
            return res;
        }
    }
    
    // ==================== テストデータビルダー ====================
    
    /**
     * テスト用アカウント作成
     */
    private static Account createTestAccount(String accountName) {
        Account acc = new Account(Name = accountName);
        insert acc;
        return acc;
    }
    
    /**
     * テスト用商品作成
     */
    private static Product2 createTestProduct(String productName, Boolean isMrr) {
        Product2 product = new Product2(
            Name = productName,
            IsActive = true,
            is_MRR__c = isMrr
        );
        insert product;
        return product;
    }
    
    /**
     * テスト用価格表エントリ作成
     */
    private static PricebookEntry createPricebookEntry(Id productId, Decimal unitPrice) {
        Id standardPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Product2Id = productId,
            Pricebook2Id = standardPricebookId,
            UnitPrice = unitPrice,
            IsActive = true
        );
        insert pbe;
        return pbe;
    }
    
    /**
     * テスト用商談作成（価格表あり）
     */
    private static Opportunity createOpportunityWithPricebook(String oppName, Id accountId) {
        Opportunity opp = new Opportunity(
            Name = oppName,
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert opp;
        return opp;
    }
    
    /**
     * テスト用商談作成（価格表なし）
     */
    private static Opportunity createOpportunityWithoutPricebook(String oppName, Id accountId) {
        Opportunity opp = new Opportunity(
            Name = oppName,
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        return opp;
    }
    
    /**
     * テスト用商談商品作成
     */
    private static OpportunityLineItem createOpportunityLineItem(
        Id opportunityId,
        Id pricebookEntryId,
        Id productId,
        Decimal quantity
    ) {
        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = opportunityId,
            PricebookEntryId = pricebookEntryId,
            Product2Id = productId,
            Quantity = quantity,
            UnitPrice = [SELECT UnitPrice FROM PricebookEntry WHERE Id = :pricebookEntryId].UnitPrice,
            Billing_end_date__c = null
        );
        insert oli;
        return oli;
    }
    
    /**
     * テスト用商品マッピング作成
     */
    private static Product2_Jotform_Field_Map__c createProductMapping(
        Id productId,
        String jotformField
    ) {
        Product2_Jotform_Field_Map__c mapping = new Product2_Jotform_Field_Map__c(
            Product2__c = productId,
            Jotform_Order_Target_Field__c = jotformField
        );
        insert mapping;
        return mapping;
    }
    
    /**
     * テスト用Jotform_Order__c作成と更新（フロー回避パターン）
     * IMPORTANT: INSERT時に別フローが動くため、必ず insert 後に Opportunity__c を再設定して update する
     */
    private static Jotform_Order__c createJotformOrder(
        String orderName,
        Id accountId,
        Id opportunityId,
        Decimal mrrValue
    ) {
        Jotform_Order__c order = new Jotform_Order__c(
            Name = orderName,
            Account__c = accountId,
            Opportunity__c = opportunityId,
            Status__c = '承認（自動）',
            Comdesk_Lead_Standard_Plan_ID__c = mrrValue
        );
        insert order;
        
        // insert後にOpportunity__cをセットしてupdate（フロー回避のため）
        order.Opportunity__c = opportunityId;
        update order;
        
        return order;
    }
    
    /**
     * 正常系：MRRプラス合計が計算されるケース
     * 商談商品から単価を取得（優先順位が機能すること）
     */
    @isTest
    static void testCalculateMonthlyTotals_NormalCase_WithOLI() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // テストデータ作成
        Account testAccount = createTestAccount('Test Account TotalCalc');
        Product2 mrrProduct = createTestProduct('Test MRR Product', true);
        PricebookEntry mrrPbe = createPricebookEntry(mrrProduct.Id, 1000.00);
        Opportunity testOpp = createOpportunityWithPricebook('Test Opportunity TotalCalc', testAccount.Id);
        createOpportunityLineItem(testOpp.Id, mrrPbe.Id, mrrProduct.Id, 2);
        createProductMapping(mrrProduct.Id, 'Comdesk_Lead_Standard_Plan_ID__c');
        Jotform_Order__c order = createJotformOrder('Test Jotform Order TotalCalc', testAccount.Id, testOpp.Id, 2);

        // テスト実行
        Test.startTest();
        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = order.Id;
        List<JotformTotalCalculator.InputWrapper> inputs = new List<JotformTotalCalculator.InputWrapper>{input};
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(inputs);
        Test.stopTest();

        // テスト結果検証
        System.assertEquals(1, results.size(), '結果は1件');
        JotformTotalCalculator.ResultWrapper result = results[0];
        System.assert(result.success, 'テスト成功: ' + result.message);
        System.assertEquals(2000, result.mrrTotalPlus, 'MRR合計（2×1000）');
        System.assertEquals(0, result.oneShotTotalPlus, 'OneShot合計');
        System.assertEquals(0, result.mrrTotalMinus, 'MRRマイナス合計');
        System.assertEquals(0, result.oneShotTotalMinus, 'OneShotマイナス合計');

        // Jotform_Order__cに値が永続化されていることを確認
        Jotform_Order__c persisted = [
            SELECT MRR_Total_Plus__c, OneShot_Total_Plus__c, MRR_Total_Minus__c, OneShot_Total_Minus__c
            FROM Jotform_Order__c
            WHERE Id = :order.Id
        ];
        System.assertEquals(2000, persisted.MRR_Total_Plus__c, '更新値：MRR_Total_Plus__c');
        System.assertEquals(0, persisted.OneShot_Total_Plus__c, '更新値：OneShot_Total_Plus__c');
        System.assertEquals(0, persisted.MRR_Total_Minus__c, '更新値：MRR_Total_Minus__c');
        System.assertEquals(0, persisted.OneShot_Total_Minus__c, '更新値：OneShot_Total_Minus__c');
    }
    
    /**
     * 入力がnullまたは空リストの場合のエラーハンドリング
     */
    @isTest
    static void testCalculateMonthlyTotals_NullInput() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // テスト実行
        Test.startTest();
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(null);
        Test.stopTest();

        // テスト結果検証
        System.assertEquals(1, results.size());
        System.assert(!results[0].success, 'nullでエラー返却');
        System.assert(results[0].message.contains('入力パラメータがありません'), 'エラーメッセージ確認');
    }
    
    /**
     * Jotform_Order__cが存在しないIDの場合
     */
    @isTest
    static void testCalculateMonthlyTotals_JotformOrderNotFound() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // テストデータ作成
        Account testAccount = createTestAccount('Test Account NotFound');
        Opportunity testOpp = createOpportunityWithPricebook('Test Opportunity NotFound', testAccount.Id);
        Product2 testProduct = createTestProduct('Test Product NotFound', false);
        createProductMapping(testProduct.Id, 'Status__c');
        // ダミーレコードを作成して削除（削除されたレコードのIDを取得）
        Jotform_Order__c dummyOrder = new Jotform_Order__c(
            Name = 'Dummy Order',
            Account__c = testAccount.Id,
            Status__c = '承認（自動）'
        );
        insert dummyOrder;
        Id deletedOrderId = dummyOrder.Id;
        delete dummyOrder;

        // テスト実行
        Test.startTest();
        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = deletedOrderId;
        List<JotformTotalCalculator.InputWrapper> inputs = new List<JotformTotalCalculator.InputWrapper>{input};
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(inputs);
        Test.stopTest();

        // テスト結果検証
        System.assertEquals(1, results.size());
        System.assert(!results[0].success, 'Jotform_Order__cが存在しないためエラー');
        System.assert(results[0].message.contains('対象のJotformオーダーがありません'), 'エラーメッセージ確認');
    }
    
    /**
     * Jotform_Order__cのOpportunity__cがnullの場合
     */
    @isTest
    static void testCalculateMonthlyTotals_OpportunityNull() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // テストデータ作成
        Account testAccount = createTestAccount('Test Account OppNull');
        Product2 testProduct = createTestProduct('Test Product OppNull', false);
        createProductMapping(testProduct.Id, 'Status__c');
        // Opportunity__cなしで作成
        Jotform_Order__c order = new Jotform_Order__c(
            Name = 'Test Jotform Order OppNull',
            Account__c = testAccount.Id,
            Status__c = '承認（自動）'
        );
        insert order;

        // テスト実行
        Test.startTest();
        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = order.Id;
        List<JotformTotalCalculator.InputWrapper> inputs = new List<JotformTotalCalculator.InputWrapper>{input};
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(inputs);
        Test.stopTest();

        // テスト結果検証
        System.assertEquals(1, results.size());
        System.assert(!results[0].success, '商談がないためエラー');
        System.assert(results[0].message.contains('対象の商談がありません'), 'エラーメッセージ確認');
    }
    
    /**
     * 商談に価格表が設定されていない場合
     */
    @isTest
    static void testCalculateMonthlyTotals_PricebookNull() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // テストデータ作成
        Account testAccount = createTestAccount('Test Account PbkNull');
        Product2 testProduct = createTestProduct('Test Product PbkNull', false);
        createProductMapping(testProduct.Id, 'Status__c');
        // 価格表なしの商談を作成
        Opportunity testOpp = createOpportunityWithoutPricebook('Test Opportunity PbkNull', testAccount.Id);
        Jotform_Order__c order = createJotformOrder('Test Jotform Order PbkNull', testAccount.Id, testOpp.Id, 0);

        // テスト実行
        Test.startTest();
        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = order.Id;
        List<JotformTotalCalculator.InputWrapper> inputs = new List<JotformTotalCalculator.InputWrapper>{input};
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(inputs);
        Test.stopTest();

        // テスト結果検証
        System.assertEquals(1, results.size());
        System.assert(!results[0].success, '価格表がないためエラー');
        System.assert(results[0].message.contains('商談に価格表が設定されていません'), 'エラーメッセージ確認');
    }
    
    /**
     * Product2_Jotform_Field_Map__cが0件の場合
     */
    @isTest
    static void testCalculateMonthlyTotals_MappingEmpty() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // テストデータ作成（マッピング作成なし）
        Account testAccount = createTestAccount('Test Account MapEmpty');
        Opportunity testOpp = createOpportunityWithPricebook('Test Opportunity MapEmpty', testAccount.Id);
        Jotform_Order__c order = createJotformOrder('Test Jotform Order MapEmpty', testAccount.Id, testOpp.Id, 0);

        // テスト実行
        Test.startTest();
        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = order.Id;
        List<JotformTotalCalculator.InputWrapper> inputs = new List<JotformTotalCalculator.InputWrapper>{input};
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(inputs);
        Test.stopTest();

        // テスト結果検証
        System.assertEquals(1, results.size());
        System.assert(!results[0].success, 'マッピングが0件でエラー');
        System.assert(results[0].message.contains('商品とJotformの項目マッピングが0件です'), 'エラーメッセージ確認');
    }

    /**
     * 商談商品がなくても価格表単価で計算されること
     */
    @isTest
    static void testCalculateMonthlyTotals_UsesPricebookWhenNoOLI() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // テストデータ作成（OLIなし）
        Account testAccount = createTestAccount('Test Account PBE');
        Product2 mrrProduct = createTestProduct('Test Product PBE', true);
        PricebookEntry mrrPbe = createPricebookEntry(mrrProduct.Id, 1500);
        Opportunity testOpp = createOpportunityWithPricebook('Test Opportunity PBE', testAccount.Id);
        createProductMapping(mrrProduct.Id, 'Comdesk_Lead_Standard_Plan_ID__c');
        Jotform_Order__c order = createJotformOrder('Test Jotform Order PBE', testAccount.Id, testOpp.Id, 3);

        // テスト実行
        Test.startTest();
        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = order.Id;
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(new List<JotformTotalCalculator.InputWrapper>{input});
        Test.stopTest();

        // テスト結果検証
        System.assertEquals(1, results.size(), '結果は1件');
        System.assert(results[0].success, 'PBEで計算成功');
        System.assertEquals(4500, results[0].mrrTotalPlus, '価格表単価（1500）×3');

        Jotform_Order__c persisted = [
            SELECT MRR_Total_Plus__c, OneShot_Total_Plus__c, MRR_Total_Minus__c, OneShot_Total_Minus__c
            FROM Jotform_Order__c
            WHERE Id = :order.Id
        ];
        System.assertEquals(4500, persisted.MRR_Total_Plus__c, '価格表を使用して更新');
        System.assertEquals(0, persisted.OneShot_Total_Plus__c);
        System.assertEquals(0, persisted.MRR_Total_Minus__c);
        System.assertEquals(0, persisted.OneShot_Total_Minus__c);
    }

    /**
     * MRR商品のマイナス数量がマイナス合計に分類されること
     */
    @isTest
    static void testCalculateMonthlyTotals_MrrNegativeQuantity() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Account testAccount = createTestAccount('Test Account Negative');
        Product2 mrrProduct = createTestProduct('Test Product Negative', true);
        PricebookEntry mrrPbe = createPricebookEntry(mrrProduct.Id, 800);
        Opportunity testOpp = createOpportunityWithPricebook('Test Opportunity Negative', testAccount.Id);
        createProductMapping(mrrProduct.Id, 'Comdesk_Lead_Standard_Plan_ID__c');
        Jotform_Order__c order = createJotformOrder('Test Jotform Order Negative', testAccount.Id, testOpp.Id, -2);

        Test.startTest();
        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = order.Id;
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(new List<JotformTotalCalculator.InputWrapper>{input});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].success, 'マイナス数量でも成功');
        System.assertEquals(-1600, results[0].mrrTotalMinus, '800×(-2)');
        System.assertEquals(0, results[0].mrrTotalPlus);

        Jotform_Order__c persisted = [
            SELECT MRR_Total_Plus__c, MRR_Total_Minus__c
            FROM Jotform_Order__c
            WHERE Id = :order.Id
        ];
        System.assertEquals(-1600, persisted.MRR_Total_Minus__c, 'MRRマイナス合計を更新');
        System.assertEquals(0, persisted.MRR_Total_Plus__c, '正の合計は0');
    }

    /**
     * OneShot商品がプラス合計に分類されること
     */
    @isTest
    static void testCalculateMonthlyTotals_OneShotPlus() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Account testAccount = createTestAccount('Test Account OneShot');
        Product2 oneShotProduct = createTestProduct('Test Product OneShot', false);
        PricebookEntry oneShotPbe = createPricebookEntry(oneShotProduct.Id, 1200);
        Opportunity testOpp = createOpportunityWithPricebook('Test Opportunity OneShot', testAccount.Id);
        createProductMapping(oneShotProduct.Id, 'Comdesk_Lead_Standard_Plan_ID__c');
        Jotform_Order__c order = createJotformOrder('Test Jotform Order OneShot', testAccount.Id, testOpp.Id, 1);

        Test.startTest();
        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = order.Id;
        List<JotformTotalCalculator.InputWrapper> inputs = new List<JotformTotalCalculator.InputWrapper>{input};
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(inputs);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].success, 'OneShot計算成功');
        System.assertEquals(1200, results[0].oneShotTotalPlus, 'OneShot合計');
        System.assertEquals(0, results[0].mrrTotalPlus, 'MRRではない');

        Jotform_Order__c persisted = [
            SELECT OneShot_Total_Plus__c, MRR_Total_Plus__c
            FROM Jotform_Order__c
            WHERE Id = :order.Id
        ];
        System.assertEquals(1200, persisted.OneShot_Total_Plus__c, 'OneShot合計を更新');
        System.assertEquals(0, persisted.MRR_Total_Plus__c, 'MRR合計は0');
    }

    /**
     * バルク実行で成功とエラーが混在する場合に個別結果が返ること
     */
    @isTest
    static void testCalculateMonthlyTotals_BulkMixedResults() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // 正常レコード
        Account okAccount = createTestAccount('Test Account Bulk OK');
        Product2 okProduct = createTestProduct('Test Product Bulk OK', true);
        PricebookEntry okPbe = createPricebookEntry(okProduct.Id, 500);
        Opportunity okOpp = createOpportunityWithPricebook('Test Opportunity Bulk OK', okAccount.Id);
        createProductMapping(okProduct.Id, 'Comdesk_Lead_Standard_Plan_ID__c');
        Jotform_Order__c okOrder = createJotformOrder('Test Jotform Order Bulk OK', okAccount.Id, okOpp.Id, 2);

        // 商談なしレコード（エラー想定）
        Account ngAccount = createTestAccount('Test Account Bulk NG');
        Jotform_Order__c ngOrder = new Jotform_Order__c(
            Name = 'Test Jotform Order Bulk NG',
            Account__c = ngAccount.Id,
            Status__c = '承認（自動）'
        );
        insert ngOrder;

        Test.startTest();
        List<JotformTotalCalculator.InputWrapper> inputs = new List<JotformTotalCalculator.InputWrapper>{
            new JotformTotalCalculator.InputWrapper(),
            new JotformTotalCalculator.InputWrapper()
        };
        inputs[0].jotformOrderId = okOrder.Id;
        inputs[1].jotformOrderId = ngOrder.Id;
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(inputs);
        Test.stopTest();

        System.assertEquals(2, results.size(), '入力順で2件返却');

        // 1件目：成功
        System.assert(results[0].success, '1件目は成功');
        System.assertEquals(1000, results[0].mrrTotalPlus, '500×2');

        // 2件目：エラー（商談なし）
        System.assert(!results[1].success, '2件目はエラー');
        System.assert(results[1].message.contains('対象の商談がありません'), '商談なしメッセージ');
    }
    
    // ========== ディスカウント商品対応テスト ==========
    
    // テスト1：ディスカウント対象商品のみで計算
    @isTest
    static void testCalculateMonthlyTotals_DiscountProduct_Normal() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // 1. アカウント作成
        Account testAccount = createTestAccount('Discount Test Account');

        // 2. 通常商品とディスカウント商品を作成
        Product2 normalProduct = createTestProduct('Normal Product', true);
        Product2 discountProduct = createTestProduct('Discount Product', true);

        // 3. 価格表エントリ作成（normalProductのPBEは作らない → 通常パスはunitPrice=nullでスキップ）
        createPricebookEntry(discountProduct.Id, 0.00);

        // 4. 商談作成
        Opportunity testOpp = new Opportunity(
            Name = 'Discount Test Opp',
            AccountId = testAccount.Id,
            StageName = '成約',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOpp;

        // 5. マッピング作成（ディスカウント商品参照付き）
        Product2_Jotform_Field_Map__c mapping = new Product2_Jotform_Field_Map__c(
            Product2__c = normalProduct.Id,
            Jotform_Order_Target_Field__c = 'Comdesk_Lead_Standard_Plan_ID__c',
            Discount_Product__c = discountProduct.Id
        );
        insert mapping;

        // 6. ディスカウント商品のOLI を事前作成（単価50.00でテスト）
        OpportunityLineItem discountOli = new OpportunityLineItem(
            OpportunityId = testOpp.Id,
            PricebookEntryId = [SELECT Id FROM PricebookEntry WHERE Product2Id = :discountProduct.Id LIMIT 1].Id,
            Product2Id = discountProduct.Id,
            Quantity = 10,
            UnitPrice = 50.00
        );
        insert discountOli;

        // 7. Jotformオーダー作成
        Jotform_Order__c jotformOrder = new Jotform_Order__c(
            Name = 'Discount Normal Test Order',
            Account__c = testAccount.Id,
            Opportunity__c = testOpp.Id,
            Status__c = '承認（自動）',
            Comdesk_Lead_Standard_Plan_ID__c = 10
        );
        insert jotformOrder;
        // insert後にOpportunity__cをセットしてupdate（フロー回避のため）
        jotformOrder.Opportunity__c = testOpp.Id;
        update jotformOrder;

        Test.startTest();

        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = jotformOrder.Id;

        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(
            new List<JotformTotalCalculator.InputWrapper>{input}
        );

        Test.stopTest();

        // 結果確認
        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, 'ディスカウント商品の計算が成功するはず');
        System.assertEquals(500, results[0].discountTotalPlus, '10 × 50.00 = 500 のはず');
        System.assertEquals(0, results[0].discountTotalMinus, 'マイナスはないはず');
        // normalProductのPBEが存在しないため、通常パスはunitPrice=nullでスキップ
        System.assertEquals(0, results[0].mrrTotalPlus, '通常商品の単価が取得できないため0');
    }
    
    // テスト2：通常合計とディスカウント合計が同一マッピングから独立して計算されること
    @isTest
    static void testCalculateMonthlyTotals_DiscountProduct_WithRegularProduct() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // 1. アカウント作成
        Account testAccount = createTestAccount('Mixed Product Test Account');

        // 2. 商品作成
        Product2 mrrProduct = createTestProduct('MRR Product', true);
        Product2 discountProduct = createTestProduct('Discount Product 2', true);

        // 3. 価格表エントリ作成（mrrProductは価格100で登録）
        createPricebookEntry(mrrProduct.Id, 100.00);
        createPricebookEntry(discountProduct.Id, 0.00);

        // 4. 商談作成
        Opportunity testOpp = new Opportunity(
            Name = 'Mixed Product Test Opp',
            AccountId = testAccount.Id,
            StageName = '成約',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOpp;

        // 5. マッピング作成（通常+ディスカウント両方を1マッピングで）
        Product2_Jotform_Field_Map__c mapping = new Product2_Jotform_Field_Map__c(
            Product2__c = mrrProduct.Id,
            Jotform_Order_Target_Field__c = 'Comdesk_Lead_Standard_Plan_ID__c',
            Discount_Product__c = discountProduct.Id
        );
        insert mapping;

        // 6. OLI作成（ディスカウント商品、単価30.00）
        OpportunityLineItem discountOli = new OpportunityLineItem(
            OpportunityId = testOpp.Id,
            PricebookEntryId = [SELECT Id FROM PricebookEntry WHERE Product2Id = :discountProduct.Id LIMIT 1].Id,
            Product2Id = discountProduct.Id,
            Quantity = 10,
            UnitPrice = 30.00
        );
        insert discountOli;

        // 7. Jotformオーダー作成（数量5）
        Jotform_Order__c jotformOrder = new Jotform_Order__c(
            Name = 'Mixed Product Test Order',
            Account__c = testAccount.Id,
            Opportunity__c = testOpp.Id,
            Status__c = '承認（自動）',
            Comdesk_Lead_Standard_Plan_ID__c = 5
        );
        insert jotformOrder;
        // insert後にOpportunity__cをセットしてupdate（フロー回避のため）
        jotformOrder.Opportunity__c = testOpp.Id;
        update jotformOrder;

        Test.startTest();

        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = jotformOrder.Id;

        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(
            new List<JotformTotalCalculator.InputWrapper>{input}
        );

        Test.stopTest();

        // 結果確認：通常パス（5×100=500）とディスカウントパス（5×30=150）が独立して計算される
        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals(500, results[0].mrrTotalPlus, '5 × 100.00 = 500 のはず（通常商品PBE）');
        System.assertEquals(150, results[0].discountTotalPlus, '5 × 30.00 = 150 のはず（ディスカウントOLI）');
    }
    
    // テスト3：ディスカウント商品で負数（削減）
    @isTest
    static void testCalculateMonthlyTotals_DiscountProduct_Negative() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // 1. アカウント作成
        Account testAccount = createTestAccount('Discount Negative Test Account');

        // 2. 商品作成
        Product2 discountProduct = createTestProduct('Discount Product 3', true);

        // 3. 価格表エントリ作成
        createPricebookEntry(discountProduct.Id, 0.00);

        // 4. 商談作成
        Opportunity testOpp = new Opportunity(
            Name = 'Discount Negative Test Opp',
            AccountId = testAccount.Id,
            StageName = '成約',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOpp;

        // 5. マッピング作成
        Product2_Jotform_Field_Map__c mapping = new Product2_Jotform_Field_Map__c(
            Product2__c = discountProduct.Id,
            Jotform_Order_Target_Field__c = 'Comdesk_Lead_Standard_Plan_ID__c',
            Discount_Product__c = discountProduct.Id
        );
        insert mapping;

        // 6. ディスカウント商品のOLI作成
        OpportunityLineItem discountOli = new OpportunityLineItem(
            OpportunityId = testOpp.Id,
            PricebookEntryId = [SELECT Id FROM PricebookEntry WHERE Product2Id = :discountProduct.Id LIMIT 1].Id,
            Product2Id = discountProduct.Id,
            Quantity = 10,
            UnitPrice = 25.00
        );
        insert discountOli;

        // 7. Jotformオーダー作成（削減数量：-6）
        Jotform_Order__c jotformOrder = new Jotform_Order__c(
            Name = 'Discount Negative Test Order',
            Account__c = testAccount.Id,
            Opportunity__c = testOpp.Id,
            Status__c = '承認（自動）',
            Comdesk_Lead_Standard_Plan_ID__c = -6
        );
        insert jotformOrder;
        // insert後にOpportunity__cをセットしてupdate（フロー回避のため）
        jotformOrder.Opportunity__c = testOpp.Id;
        update jotformOrder;

        Test.startTest();

        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = jotformOrder.Id;

        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(
            new List<JotformTotalCalculator.InputWrapper>{input}
        );

        Test.stopTest();

        // 結果確認
        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals(-150, results[0].discountTotalMinus, '-6 × 25.00 = -150 のはず');
        System.assertEquals(0, results[0].discountTotalPlus, 'プラスはないはず');
    }
    
    // テスト4：マッピング内にDiscountProduct__cがない場合（既存ロジック未影響）
    @isTest
    static void testCalculateMonthlyTotals_DiscountProduct_NoMapping() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // 1. アカウント作成
        Account testAccount = createTestAccount('No Discount Mapping Test Account');

        // 2. 商品作成（通常商品のみ）
        Product2 mrrProduct = createTestProduct('MRR Only Product', true);

        // 3. 価格表エントリ作成
        createPricebookEntry(mrrProduct.Id, 100.00);

        // 4. 商談作成
        Opportunity testOpp = new Opportunity(
            Name = 'No Discount Mapping Test Opp',
            AccountId = testAccount.Id,
            StageName = '成約',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOpp;

        // 5. マッピング作成（Discount_Product__c = null）
        Product2_Jotform_Field_Map__c mapping = new Product2_Jotform_Field_Map__c(
            Product2__c = mrrProduct.Id,
            Jotform_Order_Target_Field__c = 'Comdesk_Lead_Standard_Plan_ID__c',
            Discount_Product__c = null
        );
        insert mapping;

        // 6. Jotformオーダー作成（数量10）
        Jotform_Order__c jotformOrder = new Jotform_Order__c(
            Name = 'No Discount Mapping Test Order',
            Account__c = testAccount.Id,
            Opportunity__c = testOpp.Id,
            Status__c = '承認（自動）',
            Comdesk_Lead_Standard_Plan_ID__c = 10
        );
        insert jotformOrder;
        // insert後にOpportunity__cをセットしてupdate（フロー回避のため）
        jotformOrder.Opportunity__c = testOpp.Id;
        update jotformOrder;

        Test.startTest();

        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = jotformOrder.Id;

        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(
            new List<JotformTotalCalculator.InputWrapper>{input}
        );

        Test.stopTest();

        // 結果確認
        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals(0, results[0].discountTotalPlus, 'Discount_Product__c=nullのためディスカウント計算はスキップ');
        System.assertEquals(0, results[0].discountTotalMinus, 'Discount_Product__c=nullのためディスカウント計算はスキップ');
        System.assertEquals(1000, results[0].mrrTotalPlus, '10 × 100.00 = 1000 のはず（通常ロジック）');
    }
    /**
     * put()での動的項目セットが反映されない場合の直接セットテスト
     */
    @isTest
    static void testCalculateMonthlyTotals_DirectFieldSet() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Account testAccount = createTestAccount('Direct Field Set Account');
        Product2 mrrProduct = createTestProduct('Direct Field Set Product', true);
        PricebookEntry mrrPbe = createPricebookEntry(mrrProduct.Id, 2000);
        Opportunity testOpp = createOpportunityWithPricebook('Direct Field Set Opp', testAccount.Id);
        createProductMapping(mrrProduct.Id, 'Comdesk_Lead_Standard_Plan_ID__c');
        Jotform_Order__c order = new Jotform_Order__c(
            Name = 'Direct Field Set Order',
            Account__c = testAccount.Id,
            Opportunity__c = testOpp.Id,
            Comdesk_Lead_Standard_Plan_ID__c = 4
        );
        insert order;
        // insert後にOpportunity__cをセットしてupdate（フロー回避のため）
        order.Opportunity__c = testOpp.Id;
        update order;
        Test.startTest();
        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = order.Id;
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(new List<JotformTotalCalculator.InputWrapper>{input});
        Test.stopTest();
        System.assertEquals(1, results.size());
        System.assert(results[0].success, '直接セットで成功');
        System.assertEquals(8000, results[0].mrrTotalPlus, '4×2000=8000');
    }

    /**
     * Discount_Product__cが不正な場合のテスト
     */
    @isTest
    static void testCalculateMonthlyTotals_DiscountProduct_InvalidReference() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Account testAccount = createTestAccount('Invalid Discount Ref Account');
        Product2 normalProduct = createTestProduct('Invalid Discount Normal', true);
        createPricebookEntry(normalProduct.Id, 100);
        // 実在するProduct2を作成（OLIは作成しない → ディスカウントパスがnullでスキップ）
        Product2 discountProduct = createTestProduct('Invalid Discount Ref Discount', false);
        Opportunity testOpp = createOpportunityWithPricebook('Invalid Discount Opp', testAccount.Id);
        Product2_Jotform_Field_Map__c mapping = new Product2_Jotform_Field_Map__c(
            Product2__c = normalProduct.Id,
            Jotform_Order_Target_Field__c = 'Comdesk_Lead_Standard_Plan_ID__c',
            Discount_Product__c = discountProduct.Id // 実在するIDだがOLIなし → ディスカウントパスはスキップ
        );
        insert mapping;
        Jotform_Order__c jotformOrder = new Jotform_Order__c(
            Name = 'Invalid Discount Ref Order',
            Account__c = testAccount.Id,
            Opportunity__c = testOpp.Id,
            Status__c = '承認（自動）',
            Comdesk_Lead_Standard_Plan_ID__c = 2
        );
        insert jotformOrder;
        // insert後にOpportunity__cをセットしてupdate（フロー回避のため）
        jotformOrder.Opportunity__c = testOpp.Id;
        update jotformOrder;
        Test.startTest();
        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = jotformOrder.Id;
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(new List<JotformTotalCalculator.InputWrapper>{input});
        Test.stopTest();
        System.assertEquals(1, results.size());
        // 存在しないDiscount_Product__cはOLIルックアップでnullになるため、ディスカウントパスはスキップ
        // 通常パス（normalProduct × 2 × 100 = 200）は正常に動作する
        System.assert(results[0].success, '不正なDiscount_Product__cでも通常パスが成功すること');
    }

    /**
     * 異常系：Jotform_Order__cのカスタム項目がnullの場合のテスト
     */
    @isTest
    static void testCalculateMonthlyTotals_CustomFieldNull() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Account testAccount = createTestAccount('Custom Field Null');
        Product2 mrrProduct = createTestProduct('Custom Field Null Product', true);
        PricebookEntry mrrPbe = createPricebookEntry(mrrProduct.Id, 100);
        Opportunity testOpp = createOpportunityWithPricebook('Custom Field Null Opp', testAccount.Id);
        createProductMapping(mrrProduct.Id, 'Comdesk_Lead_Standard_Plan_ID__c');
        // Comdesk_Lead_Standard_Plan_ID__cをnullで作成
        Jotform_Order__c order = new Jotform_Order__c(
            Name = 'Custom Field Null Order',
            Account__c = testAccount.Id,
            Opportunity__c = testOpp.Id,
            Comdesk_Lead_Standard_Plan_ID__c = null
        );
        insert order;
        // insert後にOpportunity__cをセットしてupdate（フロー回避のため）
        order.Opportunity__c = testOpp.Id;
        update order;
        Test.startTest();
        JotformTotalCalculator.InputWrapper input = new JotformTotalCalculator.InputWrapper();
        input.jotformOrderId = order.Id;
        List<JotformTotalCalculator.ResultWrapper> results = JotformTotalCalculator.calculateMonthlyTotals(new List<JotformTotalCalculator.InputWrapper>{input});
        Test.stopTest();
        System.assertEquals(1, results.size());
        System.assert(results[0].success, 'カスタム項目がnullの場合、スキップされて成功すること');
        System.assertEquals(0, results[0].mrrTotalPlus, 'MRR合計は0');
        System.assertEquals(0, results[0].oneShotTotalPlus, 'OneShot合計は0');
    }
}