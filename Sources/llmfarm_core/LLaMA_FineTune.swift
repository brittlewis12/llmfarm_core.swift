//
//  LLaMA_FineTune.swift
//
//  Created by Guinmoon.
//

import Foundation
import llmfarm_core_cpp

var aaa = 1
var LLaMa_FineTune_obj_ptr:UnsafeMutableRawPointer? = nil

public class LLaMa_FineTune: FineTune {
    
    public var progressCallback: ((String)  -> ())? = nil
    public var progressCallbackExport: ((Double)  -> ())? = nil

    public override func finetune(_ progressCallback: ((String)  -> ())?) throws{
        var args = ["progr_name", "--model-base", self.model_base, "--lora-out", self.lora_out, "--train-data", self.train_data,
            "--threads", String(self.threads), "--adam-iter", String(self.adam_iter), "--batch", String(self.batch), "--ctx", String(self.ctx),
        "--checkpoint-in", String(self.lora_out + "-LATEST.gguf_"), "--checkpoint-out", String(self.lora_out + "-ITERATION.gguf_")]
        if self.use_checkpointing{
            args.append("--use-checkpointing")
        }
        if self.use_metal {
            args.append("-ngl")
            args.append("10")
        }
        do{
            print(args)
            var cargs = args.map { strdup($0) }
            self.progressCallback = progressCallback
    //        tuneQueue.async{
            self.retain_new_self_ptr()
            try ExceptionCather.catchException {
                let result = run_finetune(Int32(args.count), &cargs,
                                            { c_str in
                    let LLaMa_FineTune_obj = Unmanaged<LLaMa_FineTune>.fromOpaque(LLaMa_FineTune_obj_ptr!).takeRetainedValue()
                    if c_str != nil{
                        let for_print = String(cString:c_str!)
                        LLaMa_FineTune_obj.tune_log.append(for_print)
                        LLaMa_FineTune_obj.progressCallback!(for_print)
                        print("\nProgress: \(for_print)")
                    }
                    LLaMa_FineTune_obj.retain_new_self_ptr()
                    return LLaMa_FineTune_obj.cancel
                })
            }
            for ptr in cargs { free(ptr) }
    //        }
        }
        catch{
            print(error)
            throw error
        }
    }
    
    public func export_lora(_ progressCallback: ((Double)  -> ())?) throws{
        var args = ["progr_name", "-m", self.model_base, "-o", self.export_model,
            "-t", String(self.threads), "-s",self.lora_out, String(self.export_scale)]
        do{
            print(args)
            var cargs = args.map { strdup($0) }
            self.progressCallbackExport = progressCallback
    //        tuneQueue.async{
            self.retain_new_self_ptr()            
            try ExceptionCather.catchException {
                let result = export_lora_main(Int32(args.count), &cargs,
                                            { progress in
                    let LLaMa_FineTune_obj = Unmanaged<LLaMa_FineTune>.fromOpaque(LLaMa_FineTune_obj_ptr!).takeRetainedValue()
                    let for_print = String(progress)
                    LLaMa_FineTune_obj.tune_log.append(for_print)
                    LLaMa_FineTune_obj.progressCallbackExport!(progress)
                    print("\nProgress: \(progress)")
                    LLaMa_FineTune_obj.retain_new_self_ptr()
                    return LLaMa_FineTune_obj.cancel
                })
            }
            for ptr in cargs { free(ptr) }
    //        }
        }
        catch{
            print(error)
            throw error
        }
    }
    
    private func retain_new_self_ptr(){
        LLaMa_FineTune_obj_ptr = Unmanaged.passRetained(self).toOpaque()
    }
    
}


