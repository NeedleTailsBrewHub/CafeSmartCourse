//
//  HTTPMediaType.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/26/25.
//
import Vapor

extension HTTPMediaType {
  public static var bson: HTTPMediaType {
    HTTPMediaType(type: "application", subType: "bson")
  }
}
