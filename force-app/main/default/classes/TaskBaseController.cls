public class TaskBaseController{

    /**
    * トランのタスク
    * タスクを取得
    * */
    @AuraEnabled
    public static List<SObject> getTaskListofTran(String cTaskObjectAPI, Id recordId){
        try{
            //格納先
            List<SObject> createdTaskList = new List<SObject>();
            //mainTaskリスト
            List<SObject> mTaskList = getMainTasksofTran(cTaskObjectAPI,recordId);
            //リスト作成
            for (SObject mTask:mTaskList) {
                //mainTaskを「taskMasterList」に追加
                createdTaskList.add(mTask);
                //subTaskリスト
                List<SObject> sTaskList = getSubTasksofTran(mTask.Id, cTaskObjectAPI, recordId);
                //mainTaskに紐付くsubTaskを「taskMasterList」に追加
                createdTaskList.addAll(sTaskList);
            }
            return createdTaskList;
        }catch (Exception e){
            throw e;
        }
    }
	
    /**
     * componentが置いてあるobject名取得
     * */
    public static String getObjectAPI(Id recordId){
        Schema.SObjectType sobjectType = recordId.getSObjectType();
        return sobjectType.getDescribe().getName();
    }
    
    /**
    * トランのタスク
    * mainタスクを取得
    * 条件：
    * recordType.Name = 'Main'
    * MasterObject__c(紐づく主オブジェクト)
    * */
    public static List<SObject> getMainTasksofTran(String cTaskObjectAPI, Id recordId){
        List<SObject> createdTaskList = Database.query('SELECT Id, RecordType.Name, Name, text1__c, date__c, days__c, user__r.Name, user__c, Status__c, DisplayNum__c, MasterObject__c'
                                                       +' FROM '+cTaskObjectAPI
                                                       +' WHERE recordType.Name = \'Main\''
                                                       +' AND MasterObject__c = :recordId'
                                                       +' order by DisplayNum__c');
        return createdTaskList;
    }

    /**
    * トランのタスク
    * mainタスクのsubタスクを取得
    * 条件：
    * TaskMaster__c(紐づく主タスク)
    * recordType.Name = 'Sub'
    * */
    public static List<SObject> getSubTasksofTran(Id mainTaskId, String cTaskObjectAPI, Id recordId){
        List<SObject> createdTaskList = Database.query('SELECT Id, RecordType.Name, Name, text1__c, date__c, days__c, user__r.Name, user__c, Status__c, DisplayNum__c, MasterObject__c'
                                                       +' FROM '+ cTaskObjectAPI
                                                       +' WHERE TaskMaster__c=\''+ mainTaskId+'\''
                                                       +' And recordType.Name = \'Sub\''
                                                       +' order by DisplayNum__c');
        return createdTaskList;
    }

    /**
    * TaskMaster
    * mainタスクに紐付くsubタスク関係を持つリスト作成
    * */
    @AuraEnabled
    public static Object getTaskList(Id templateId, String objectAPI, String userIdAPI, String dateAPI, Id recordId, Boolean holidayChk){
        try{
            //格納先
            List<TaskMaster__c> taskMasterList = new List<TaskMaster__c>();
            //mainTaskリスト
            List<TaskMaster__c> mTaskList = getMainTasks(templateId);
            //リスト作成
            for (TaskMaster__c mTask:mTaskList) {
                //mainTaskを「taskMasterList」に追加
                taskMasterList.add(mTask);
                //subTaskリスト
                List<TaskMaster__c> sTaskList = getSubTasks(mTask.Id);
                //mainTaskに紐付くsubTaskを「taskMasterList」に追加
                taskMasterList.addAll(sTaskList);
            }
            //基準日取得
            Date startDate = getStartDate(objectAPI, dateAPI, recordId);
            //期日の設定
            setDueDate(taskMasterList, startDate, holidayChk);
            
            //担当者Id取得
            Id userId = getUserId(objectAPI, userIdAPI, recordId);
            //担当者設定
            setUser(taskMasterList, userId);
            
            return taskMasterList;
        }catch(Exception e){
            throw new AuraHandledException('TaskBaseController.getTaskList : ' + e.getMessage());
        }
    }

    /**
    * TaskMaster
    * mainタスクを取得
    * 条件：Template__c
    */
    public static List<TaskMaster__c> getMainTasks(Id templateId){
        List<TaskMaster__c> taskMasterList = [SELECT Id, RecordType.Name, Name, text1__c, days__c, template__c, DisplayNum__c
                                              FROM TaskMaster__c
                                              WHERE Template__c =:templateId
                                              And recordType.Name = 'Main'
                                              order by DisplayNum__c];
        return taskMasterList;
    }
   

    /**
    * TaskMaster
    * mainタスクのsubタスクを取得
    * 条件：TaskMaster__c
    */
    public static List<TaskMaster__c> getSubTasks(Id mainTaskId){
        List<TaskMaster__c> taskMasterList = [SELECT Id, RecordType.Name, Name, text1__c, days__c, template__c, DisplayNum__c
                                              FROM TaskMaster__c
                                              WHERE TaskMaster__c=:mainTaskId
                                              And recordType.Name = 'Sub'
                                              order by DisplayNum__c];
        return taskMasterList;
    }

    /**
     * 基準日を取得
     * */
    public static Date getStartDate(String objectAPI, String dateAPI, String recordId){
        List<sObject> sobjList;
        Date startDate = null;

        if(objectAPI != null && dateAPI != null && recordId != null){
            //Query文作成
            sobjList = Database.query('SELECT '+dateAPI+',Name FROM '+objectAPI+' WHERE Id IN (\''+ recordId +'\')');
            //基準日取得
            for(sObject s:sobjList) {
                startDate = (Date) s.get(dateAPI);
            }
        }
        return startDate;
    }

    /**
     * TaskMaster__c　→　component
     * 期日を設定
     * 今日の日付から日数を加算する
     * */
    public static void setDueDate(List<TaskMaster__c> taskMasterList, Date startDate, Boolean holidayChk){
        
        //基準日から休日リスト取得
        List<Holiday__c> holidayList = [SELECT Id, date__c 
                                        FROM Holiday__c
                                        WHERE date__c >= :startDate
                                        ORDER BY date__c ASC];
        
        for(TaskMaster__c tm:taskMasterList){
            //日数取得
            Integer days = Integer.valueOf(tm.days__c);
            //日数が未入力の場合
            if(days == null){
                //0日に設定する
                days = 0;
            }

            //基準日が未入力の場合
            if(startDate == null){
                //期日を空にする
                tm.date__c = null;
            } else {
                if(holidayChk){
                    //休日計算(全部)
                    tm.date__c = checkHolidayAll(holidayList, startDate, startDate.addDays(days));
                }else{
               		//基準日から日数を加算
            		tm.date__c = startDate.addDays(days);
                }                
            }
        }
    }

    /**
     * userId取得
     */
    public static Id getUserId(String objectAPI, String userIdAPI, Id recordId){
        try{
            Id userId = null;
            List<sObject> sobjList;
            if(objectAPI != null && userIdAPI != null && recordId != null){
                //Query文作成
                sobjList = Database.query('SELECT '+userIdAPI+',Name FROM '+objectAPI+' WHERE Id IN (\''+ recordId +'\')');
                //Id取得
                for(sObject s:sobjList){
                    userId = (Id) s.get(userIdAPI);
                }
            }
            return userId;            
        }catch(Exception e){
            //throw new AuraHandledException('getUserId : ' + e.getMessage());
            throw e;
        }
    }

    /**
     * TaskMaster__c　→　component
     * 担当者を設定する
     * */
    public static void setUser(List<TaskMaster__c> taskMasterList, Id userId){
        User u = [SELECT Id, Name FROM User WHERE Id =:userId Limit 1];
        for(TaskMaster__c tm:taskMasterList){
            tm.user__c = userId;
            if(u.Id != null){
                tm.user__r = u;
            }
        }
    }

    /**
    * トランのタスク
    * Createボタンを押下時、
    * トランのタスクにタスク追加する
    */
    @AuraEnabled
    public static List<SObject> setTasks(List<SObject> TaskList, List<Id> pDelList, String cTaskObjectAPI, Id recordId){
        try{
            //delボタンで行削除で削除されたタスクをトランのタスクから削除
            deleteTask(pDelList,cTaskObjectAPI);
            
            //main task Id
            Id mainId;
            //RecordType Id
            Id RecId;
            //count
            Integer cnt=0;
            //user Id
            Id userId = null;
            User userIdR = null;
            
            for(SObject task :TaskList){
                //タスク入力先のカスタムオブジェックト型を生成
                //Convert to schema.sObjectType
                Schema.SObjectType convertType = Schema.getGlobalDescribe().get(cTaskObjectAPI);
                //Create an instance of that type
                Sobject t = convertType.newSObject();
                
                //トランのタスクか確認（true：トランのタスク, false : その他）
                Boolean isTran = task.getSObjectType().getdescribe().getname().equals(cTaskObjectAPI);
                
                //「担当者」
                userId = (Id)task.get('user__c');
                
                //「レコードタイプ」
                //レコードタイプがmainの場合
                if(task.get('RecordTypeId').equals(getRecIdinTM('Main')) ||
                   task.get('RecordTypeId').equals(getRecIdinCT(cTaskObjectAPI, 'Main'))){
                       //レコードタイプをmainにする
                       RecId = getRecIdinCT(cTaskObjectAPI, 'Main');
                       //サブに紐付けるためのmainIdをクリアする
                       mainId = null;
                   }else{
                       ///レコードタイプをsubにする
                       RecId = getRecIdinCT(cTaskObjectAPI, 'Sub');
                   }
                
                //トランのレコードの場合
                if(isTran){
                    t = task;
                    t.put('RecordTypeId',RecId);
                }else{
                    t.put('Name',task.get('Name'));
                    t.put('RecordTypeId',RecId);
                    t.put('text1__c',(String)task.get('text1__c'));
                    t.put('date__c',(Date)task.get('date__c'));
                    t.put('user__c',userId);
                    t.put('Status__c',(String)task.get('Status__c'));
                }
                
                t.put('DisplayNum__c',++cnt);
                t.put('TaskMaster__c',mainId);
                t.put('MasterObject__c',recordId);
                t.put('selectedFlg__c',false);
                upsert t;
                
                if(task.get('RecordTypeId').equals(getRecIdinTM('Main')) ||
                   task.get('RecordTypeId').equals(getRecIdinCT(cTaskObjectAPI, 'Main'))){
                       //サブに紐付けるためのmainIdを保持する
                       mainId = t.Id;
                   }
            }
            
            //トランタスクリスト取得
            List<SObject> taskMasterList = getTaskListofTran(cTaskObjectAPI, recordId);
            return taskMasterList;
        }catch(Exception e){
            throw new AuraHandledException('TaskBaseController: setTasks: ' + e.getMessage());
        }
    }

    /**
    * RecordTypeIdを取得
    * */
    public static Id getRecIdinCT(String cTaskObjectAPI, String RecName){
        return Schema.getGlobalDescribe().get(cTaskObjectAPI).getDescribe().getRecordTypeInfosByName()
            	.get(RecName).getRecordTypeId();
    }
    
    /**
    * タスクマスタのRecordTypeIdを取得
    * */
    public static Id getRecIdinTM(String RecName){
        return Schema.SObjectType.TaskMaster__c.getRecordTypeInfosByDeveloperName()
            .get(RecName).getRecordTypeId();
    }

    /**
     * トランのレコード削除
     * */
    public static void deleteTask(List<Id> pDelList, String cTaskObjectAPI){
        if(pDelList != null){
            List<SObject> ct = Database.query('SELECT Id, Name'
                                              +' FROM ' + cTaskObjectAPI
                                              +' WHERE Id IN :pDelList');
            delete ct;
        }
    }

    /**
     * ステータスのリスト取得
     * */
    public static List<Map<String, String>> getStatusListItem(String cTaskObjectAPI){
        List<Map<String, String>> optionList = new List<Map<String, String>>();
        Schema.SObjectType sObjType = (Schema.SObjectType) Schema.getGlobalDescribe().get(cTaskObjectAPI);
        if(sObjType != null){
            Map<String, Schema.SObjectField> fieldmap = sObjType.getDescribe().fields.getMap();
            Schema.SObjectField f = (Schema.SObjectField) fieldmap.get('Status__c');
            if(f != null){
                Schema.DescribeFieldResult r = f.getDescribe();
                List<Schema.PicklistEntry> pickList = r.getPicklistValues();
                for(Schema.PicklistEntry pick:pickList){
                    Map<String, String> itemMap = new Map<String, String>();
                    itemMap.put('label', String.valueOf(pick.getLabel()));
                    itemMap.put('value', String.valueOf(pick.getValue()));
                    optionList.add(itemMap);
                }
            }
        }
        return optionList;
    }
    
    /**
     * 休日計算
     * 期間中のすべての休日を加算
     * */
    public static Date checkHolidayAll(List<Holiday__c> pHolidayList, Date pStartDate, Date pEndDate){
        Date endDate = pEndDate;
        for(Holiday__c hd : pHolidayList){
            //期日まで休日がある場合
            if(endDate >= hd.Date__c){
                endDate = endDate +1 ;
            }else{
                break;
            }
        }        
        return endDate;
    }

	/*
	 * オブジェクトのprefix取得
	 * */    
    public static String getPrefix(String cTaskObjectAPI){
        String prefix =  Schema.getGlobalDescribe().get(cTaskObjectAPI).getDescribe().getKeyPrefix();
        return prefix;
    }
    
    
    /**
     * 初期処理
     * */
    @AuraEnabled
    public static Map<String, Object> initDo(Id recordId, String cTaskObjectAPI, String userIdAPI, String dateAPI){
        try{
            Map<String, Object> initMap = new Map<String, Object>();
            
            //componentが置いてあるobject名
            String objectAPI = getObjectAPI(recordId);
            initMap.put('objectAPI', objectAPI);
            
            //担当者Id取得
            Id userId = getUserId(objectAPI,userIdAPI,recordId);  
            initMap.put('userId', userId);
            
            //基準日取得
            Date startDate = getStartDate(objectAPI, dateAPI, recordId);
            initMap.put('startDate', startDate);
            
            //ステータスのリスト取得
            List<Map<String, String>> statusList = getStatusListItem(cTaskObjectAPI);
            initMap.put('statusList', statusList);
            
            //レコードId取得
            Id mainTaskRecordTypeId = getRecIdinCT(cTaskObjectAPI, 'Main');
            Id subTaskRecordTypeId = getRecIdinCT(cTaskObjectAPI, 'Sub');
            initMap.put('mainTaskRecordTypeId', mainTaskRecordTypeId);
            initMap.put('subTaskRecordTypeId', subTaskRecordTypeId);
            
            //トランタスクリスト取得
            List<SObject> taskMasterList = getTaskListofTran(cTaskObjectAPI, recordId);
            initMap.put('taskMasterList', taskMasterList);
            
            //トランタスクリストのprefix取得
            String prefix = getPrefix(cTaskObjectAPI);
            initMap.put('prefix', prefix);
            
            return initMap;            
        }catch(Exception e){
            throw new AuraHandledException('TaskBaseController: initDo : ' + e.getMessage());
        }
    }
}