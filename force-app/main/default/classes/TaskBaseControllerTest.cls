@isTest
public class TaskBaseControllerTest {
    @isTest static void testGetObjectAPI(){
        Account a = new Account(Name='TestAccount');
        insert a;
        String objectAPI = TaskBaseController.getObjectAPI(a.Id);
        System.assertEquals('Account', objectAPI);
    }
    
    
    @isTest static void testGetTaskList(){
        
        Template__c temp = new Template__c(Name='TestTemplate');
        insert temp;
        
        //recordId
        String recordIdM = Schema.SObjectType.TaskMaster__c.getRecordTypeInfosByDeveloperName()
            .get('Main').getRecordTypeId();
        String recordIdS = Schema.SObjectType.TaskMaster__c.getRecordTypeInfosByDeveloperName()
            .get('Sub').getRecordTypeId();
        
        for(Integer i=0;i<5;i++){
            TaskMaster__c taskMasterM = new TaskMaster__c();
            taskMasterM.put('RecordTypeId', recordIdM);
            taskMasterM.put('Name', 'test' + i);
            taskMasterM.put('text1__c', 'text' + i);
            taskMasterM.put('days__c', 1);
            taskMasterM.put('template__c', temp.Id);
            
            insert taskMasterM;
            
            for(Integer k=0;k<5; k++){
           		TaskMaster__c taskMasterS = new TaskMaster__c();
                taskMasterS.put('RecordTypeId', recordIdS);
                taskMasterS.put('Name', 'test' + k);
                taskMasterS.put('text1__c', 'text' + k);
                taskMasterS.put('days__c', null);
                taskMasterS.put('TaskMaster__c', taskMasterM.Id);  
                
		        insert taskMasterS;
            }
        }
        //get recordId
        //case1:date is not null
        Opportunity opp1 = new Opportunity(Name='TestOpp', CloseDate = date.today(), StageName='Prospecting');
        //case2:date is null
        insert opp1;

        Test.startTest();
        Object taskList = TaskBaseController.getTaskList(temp.Id, 'Opportunity', 'OwnerId', 'CloseDate', opp1.Id, true);
        //List<TaskMaster__c> taskList2 = TaskBaseController.getTaskList(temp.Id, 'Opportunity', 'OwnerId', 'CloseDate', opp1.Id, false);
        Test.stopTest();
    }
    
    @isTest static void testGetMainTasksofTran(){
        
        //recordTypeId
        String recordIdM = Schema.SObjectType.CreatedTask__c.getRecordTypeInfosByDeveloperName()
            .get('Main').getRecordTypeId();
        String recordIdS = Schema.SObjectType.CreatedTask__c.getRecordTypeInfosByDeveloperName()
            .get('Sub').getRecordTypeId();
        
        Integer cnt =0;
        
        Opportunity opp = new Opportunity(Name='TestOpp', CloseDate = date.today(), StageName='Prospecting');
		insert opp;
        
        for(Integer i=0;i<5;i++){
       		CreatedTask__c ctM = new CreatedTask__c();
            ctM.put('RecordTypeId', recordIdM);
            ctM.put('Name', 'test' + i);
            ctM.put('text1__c', 'text' + i);
            ctM.put('date__c', date.today());
            ctM.put('DisplayNum__c', cnt++);
            ctM.put('MasterObject__c', opp.Id);
            
            insert ctM;
            
            for(Integer k=0;k<5; k++){
           		CreatedTask__c ctS = new CreatedTask__c();
                ctS.put('RecordTypeId', recordIdS);
                ctS.put('Name', 'test' + i);
                ctS.put('text1__c', 'text' + i);
                ctS.put('date__c', date.today());
                ctS.put('DisplayNum__c', cnt++);
                ctS.put('MasterObject__c', opp.Id);  
            	ctS.put('TaskMaster__c', ctM.Id);
                
		        insert ctS;
            }
        }
        
        Test.startTest();
        List<SObject> createdTaskList = TaskBaseController.getTaskListofTran('CreatedTask__c',opp.Id);       
        Test.stopTest();   
    }
    
    @isTest static void testSetTasks(){
        Opportunity opp = new Opportunity(Name='TestOpp', CloseDate = date.today(), StageName='Prospecting');
		insert opp;
        
        //recordTypeId
        String recordIdM = Schema.SObjectType.CreatedTask__c.getRecordTypeInfosByDeveloperName()
            .get('Main').getRecordTypeId();
        String recordIdS = Schema.SObjectType.CreatedTask__c.getRecordTypeInfosByDeveloperName()
            .get('Sub').getRecordTypeId();
        
        Integer cnt = 0;
        
        List<CreatedTask__c> ctList = new List<CreatedTask__c>();
        for(Integer i=0;i<5;i++){
       		CreatedTask__c ctM = new CreatedTask__c();
            ctM.put('RecordTypeId', recordIdM);
            ctM.put('Name', 'test' + i);
            ctM.put('text1__c', 'text' + i);
            ctM.put('date__c', date.today());
            ctM.put('DisplayNum__c', cnt++);
            //ctM.put('MasterObject__c', opp.Id);
            
            insert ctM;
            ctList.add(ctM);
            
            for(Integer k=0;k<5; k++){
           		CreatedTask__c ctS = new CreatedTask__c();
                ctS.put('RecordTypeId', recordIdS);
                ctS.put('Name', 'test' + i);
                ctS.put('text1__c', 'text' + i);
                ctS.put('date__c', date.today());
                ctS.put('DisplayNum__c', cnt++);
                //ctS.put('MasterObejct__c', opp.Id);  
            	ctS.put('TaskMaster__c', ctM.Id);
                
                insert ctS;                
                ctList.add(ctS);
            }
        }
        
        Test.startTest();
        //List<SObject> TaskList, List<Id> pDelList, String cTaskObjectAPI, Id recordId
        TaskBaseController.setTasks(ctList, null, 'CreatedTask__c',opp.Id);  
        Test.stopTest(); 
    }
    
        
    @isTest static void testDeleteTask(){
        
        CreatedTask__c ct = new CreatedTask__c(Name = 'TestCreatedTask');
        insert ct;
        
        List<Id> pDelList = new List<Id>();
        pDelList.add(ct.Id);
        
        Test.startTest();
        //deleteTask(List<Id> pDelList, String cTaskObjectAPI)
        TaskBaseController.deleteTask(pDelList,'CreatedTask__c');
        Test.stopTest(); 
    }
    
    @isTest static void testGetStatusListItem(){
        //(String cTaskObjectAPI)
        Test.startTest();
        TaskBaseController.getStatusListItem('CreatedTask__c');
        Test.stopTest();
    }
    
    /*
     * customLookUpController.cls
     * */
    @isTest static void testCustomLookUpController(){
        List<Opportunity> oppList = new List<Opportunity>();
        for (Integer i=0;i<5;i++){
            Opportunity opp = new Opportunity(Name='TestOpp'+i,
                                              CloseDate = date.today(),
                                              StageName='Prospecting');
            oppList.add(opp);
        }
        insert oppList;
        
        Test.startTest();
        //String searchKeyWord, String ObjectName
        customLookUpController.fetchLookUpValues('Test','Opportunity');
        Test.stopTest(); 
    }
    
    @isTest static void testInitDo(){
        
        Opportunity opp = new Opportunity(Name='TestOpp', CloseDate = date.today(), StageName='Prospecting');
		insert opp;
        Test.startTest();
        //public static Map<String, Object> initDo(Id recordId, String cTaskObjectAPI){
        TaskBaseController.initDo(opp.Id,'CreatedTask__c','OwnerId', 'CloseDate');
        Test.stopTest(); 
    }
}